//
//  AIModel.swift
//  TTB
//
//  Created by AI Assistant on 2025-07-18.
//

import Foundation
import FirebaseFirestore
import FirebaseAuth

// MARK: - AI Usage Service Protocol
protocol AIUsageServiceProtocol {
    func getUsageStats() async throws -> AIUsageStats
    func updateUsageStats(_ stats: AIUsageStats) async throws
    func canMakeQuery() async throws -> Bool
}

@MainActor
class AIModel: ObservableObject {
    // MARK: - Published Properties
    @Published private(set) var queries: [AIQuery] = []
    @Published private(set) var recentQueries: [AIQuery] = []
    @Published private(set) var isLoading = false
    @Published private(set) var usageStats = AIUsageStats()
    @Published var error: String?
    @Published var currentQuery: String = ""
    @Published var selectedCategory: AICategory = .other
    @Published var showingHistory = false
    @Published var showingUsageDetails = false
    
    // MARK: - Private Properties
    private let aiService: AIServiceProtocol
    private let usageService: AIUsageServiceProtocol
    private var queriesListener: ListenerRegistration?
    private let maxRecentQueries = 10
    private var hasLoadedUsageStats = false
    private var admission = UsageAdmissionState()
    private let anonymousUserProvider: () -> Bool

    // MARK: - Computed Properties
    var isAnonymousUser: Bool {
        anonymousUserProvider()
    }

    var dailyLimit: Int {
        GuestCapabilityPolicy.dailyAILimit(isAnonymous: isAnonymousUser)
    }

    var weeklyLimit: Int {
        usageStats.weeklyLimit
    }

    var monthlyLimit: Int {
        usageStats.monthlyLimit
    }

    var canMakeQuery: Bool {
        hasLoadedUsageStats && Self.hasCapacity(
            currentCount: usageStats.dailyQueries,
            limit: dailyLimit,
            reservations: admission.reservedRequestCount
        ) && Self.hasCapacity(
            currentCount: usageStats.weeklyQueries,
            limit: weeklyLimit,
            reservations: admission.reservedRequestCount
        ) && Self.hasCapacity(
            currentCount: usageStats.monthlyQueries,
            limit: monthlyLimit,
            reservations: admission.reservedRequestCount
        )
    }

    /// Checks if the AI service is generally available.
    /// Use this to enable/disable UI elements that open the query input view.
    var isServiceAvailable: Bool {
        canMakeQuery
    }
    
    /// Checks if the current query text is valid for submission.
    /// Use this for the actual submission button inside the input view.
    var canSubmitQuery: Bool {
        return isServiceAvailable && isCurrentQueryValid
    }
    
    var isCurrentQueryValid: Bool {
        let trimmed = currentQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count >= 3 && trimmed.count <= 200
    }

    var serviceStatusMessage: String? {
        guard !canMakeQuery else { return nil }

        if isAnonymousUser {
            return String(
                format: String(localized: "ai.usage.guestLimitReached"),
                locale: AppLocalization.currentLocale,
                dailyLimit
            )
        }

        return String(localized: "ai.usage.limitReached")
    }
    
    // MARK: - Initialization
    init(
        aiService: AIServiceProtocol? = nil,
        usageService: AIUsageServiceProtocol? = nil,
        isAnonymousUser: @escaping () -> Bool = { Auth.auth().currentUser?.isAnonymous ?? false }
    ) {
        self.anonymousUserProvider = isAnonymousUser
        if let aiService = aiService {
            self.aiService = aiService
        } else {
            // Use MockAIService for development/testing
            self.aiService = AIService()
        }
        
        if let usageService = usageService {
            self.usageService = usageService
        } else if let currentUser = Auth.auth().currentUser {
            self.usageService = AIUsageService(userId: currentUser.uid)
        } else {
            self.usageService = AIUsageService(userId: "anonymous")
        }
        
        Task { @MainActor in
            await self.loadInitialData()
        }
    }
    
    // MARK: - Public Methods
    func askQuestion(_ question: String, category: AICategory) async {
        guard isServiceAvailable else { return }
        
        let trimmedQuestion = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuestion.isEmpty else { return }

        let submittedDraft = currentQuery
        let requestID = UUID()
        admission.latestRequestID = requestID
        admission.activeRequestCount += 1
        admission.reservedRequestCount += 1
        admission.admissionToken = UUID()
        var holdsReservation = true
        isLoading = true
        error = nil
        defer {
            if holdsReservation {
                admission.reservedRequestCount -= 1
            }
            admission.activeRequestCount -= 1
            isLoading = admission.activeRequestCount > 0
        }
        
        // Create a loading query
        let loadingQuery = AIQuery(
            question: trimmedQuestion,
            category: category,
            isLoading: true
        )
        
        // Add to recent queries immediately
        recentQueries.insert(loadingQuery, at: 0)
        
        let responses: [String]
        do {
            responses = try await aiService.askQuestion(trimmedQuestion, category: category)
        } catch {
            let errorQuery = AIQuery(
                id: loadingQuery.id,
                question: trimmedQuestion,
                category: category,
                isLoading: false,
                error: error.localizedDescription
            )
            
            // Update recent queries
            if let index = recentQueries.firstIndex(where: { $0.id == loadingQuery.id }) {
                recentQueries[index] = errorQuery
            }
            
            if admission.latestRequestID == requestID {
                self.error = error.localizedDescription
            }
            return
        }

        let completedQuery = AIQuery(
            id: loadingQuery.id,
            question: trimmedQuestion,
            responses: responses,
            category: category,
            isLoading: false
        )

        if let index = recentQueries.firstIndex(where: { $0.id == loadingQuery.id }) {
            recentQueries[index] = completedQuery
        }

        admission.reservedRequestCount -= 1
        holdsReservation = false

        let persistenceError = await recordAndPersistUsage(category: category)

        // Apply outcomes only if this request is still the latest; a newer submit
        // supersedes both the error surface and the draft clear. No suspension point
        // separates these writes, so one identity check covers both.
        if admission.latestRequestID == requestID {
            if let persistenceError {
                self.error = persistenceError
            }

            if currentQuery == submittedDraft,
               submittedDraft.trimmingCharacters(in: .whitespacesAndNewlines) == trimmedQuestion {
                currentQuery = ""
            }
        }
    }

    /// Applies the usage increment locally, then persists it only after any earlier persist
    /// finishes, so concurrent submits write in submit order. Advances the synchronized
    /// revision on success and returns a localized message on failure, or `nil` on success.
    private func recordAndPersistUsage(category: AICategory) async -> String? {
        usageStats = usageStats.incrementUsage(category: category)
        admission.revision &+= 1
        let statsToPersist = usageStats
        let revisionToPersist = admission.revision
        let precedingPersistenceTask = admission.persistenceTask
        let persistenceTask = Task<String?, Never> { @MainActor [usageService] in
            _ = await precedingPersistenceTask?.value

            do {
                try await usageService.updateUsageStats(statsToPersist)
                return nil
            } catch {
                return error.localizedDescription
            }
        }
        admission.persistenceTask = persistenceTask

        let persistenceError = await persistenceTask.value
        if persistenceError == nil {
            admission.synchronizedRevision = max(
                admission.synchronizedRevision,
                revisionToPersist
            )
        }
        return persistenceError
    }
    
    func saveQuery(_ query: AIQuery) async {
        guard let currentUser = Auth.auth().currentUser else { return }
        
        do {
            let savedQuery = AIQuery(
                id: query.id,
                question: query.question,
                responses: query.responses,
                timestamp: query.timestamp,
                category: query.category,
                isSaved: true,
                isLoading: query.isLoading,
                error: query.error
            )
            
            // Save to Firebase
            let db = Firestore.firestore()
            try await db.collection("users")
                .document(currentUser.uid)
                .collection("aiQueries")
                .document(query.id)
                .setData(savedQuery.toFirestore())
            
            // Update local state
            if let index = recentQueries.firstIndex(where: { $0.id == query.id }) {
                recentQueries[index] = savedQuery
            }
            
            if let index = queries.firstIndex(where: { $0.id == query.id }) {
                queries[index] = savedQuery
            } else {
                queries.append(savedQuery)
            }
            
        } catch {
            self.error = String(
                format: String(localized: "ai.model.error.saveQuery"),
                locale: AppLocalization.currentLocale,
                error.localizedDescription
            )
        }
    }
    
    func deleteQuery(_ query: AIQuery) async {
        guard let currentUser = Auth.auth().currentUser else { return }
        
        do {
            // Delete from Firebase
            let db = Firestore.firestore()
            try await db.collection("users")
                .document(currentUser.uid)
                .collection("aiQueries")
                .document(query.id)
                .delete()
            
            // Update local state
            recentQueries.removeAll { $0.id == query.id }
            queries.removeAll { $0.id == query.id }
            
        } catch {
            self.error = String(
                format: String(localized: "ai.model.error.deleteQuery"),
                locale: AppLocalization.currentLocale,
                error.localizedDescription
            )
        }
    }
    
    func convertToQuestion(_ query: AIQuery) async {
        guard let currentUser = Auth.auth().currentUser,
              query.isComplete else { return }
        
        do {
            let creatorUsername = try await currentUsername(for: currentUser.uid)

            // Create a new Question object
            let question = Question(
                id: UUID().uuidString,
                text: query.question,
                category: convertAICategoryToQuestionCategory(query.category),
                source: .userCreated,
                answers: [], // Empty answers initially
                isFavorite: false,
                createdAt: Date(),
                createdBy: currentUser.uid,
                creatorUsername: creatorUsername,
                isAnnounced: false,
                moderationStatus: .pending,
                featuredPlacement: .none,
                lastAnsweredAt: nil
            )
            
            // Save to Firebase questions collection
            let db = Firestore.firestore()
            try await db.collection("questions")
                .document(question.id)
                .setData(question.toFirestore())
            
            // Show success message
            // In a real app, you might show a toast or navigation
            
        } catch {
            self.error = String(
                format: String(localized: "ai.model.error.createQuestion"),
                locale: AppLocalization.currentLocale,
                error.localizedDescription
            )
        }
    }

    private func currentUsername(for userId: String) async throws -> String? {
        let db = Firestore.firestore()
        let snapshot = try await db.collection("users").document(userId).getDocument()
        let username = (snapshot.data()?["username"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return username?.isEmpty == false ? username : nil
    }
    
    func loadQueries() async {
        guard let currentUser = Auth.auth().currentUser else { return }
        
        do {
            let db = Firestore.firestore()
            let snapshot = try await db.collection("users")
                .document(currentUser.uid)
                .collection("aiQueries")
                .order(by: "timestamp", descending: true)
                .getDocuments()
            
            let loadedQueries = snapshot.documents.compactMap { doc in
                AIQuery.fromFirestore(doc.data(), id: doc.documentID)
            }
            
            self.queries = loadedQueries
            
        } catch {
            self.error = String(
                format: String(localized: "ai.model.error.loadHistory"),
                locale: AppLocalization.currentLocale,
                error.localizedDescription
            )
        }
    }
    
    func loadUsageStats() async {
        if admission.isLoadingStats {
            await withCheckedContinuation { continuation in
                admission.loadWaiters.append(continuation)
            }
            return
        }

        admission.isLoadingStats = true
        await performUsageStatsLoad()
    }

    private func performUsageStatsLoad(
        expectedRevision: UInt? = nil
    ) async {
        defer {
            admission.isLoadingStats = false
            let waiters = admission.loadWaiters
            admission.loadWaiters.removeAll()
            waiters.forEach { $0.resume() }
        }

        _ = await admission.persistenceTask?.value

        let revisionAtRequest = expectedRevision ?? admission.revision
        let admissionTokenAtRequest = admission.admissionToken
        guard
            revisionAtRequest == admission.revision,
            revisionAtRequest == admission.synchronizedRevision,
            admission.reservedRequestCount == 0
        else {
            return
        }

        do {
            let stats = try await usageService.getUsageStats()
            guard
                revisionAtRequest == admission.revision,
                admission.revision == admission.synchronizedRevision,
                admissionTokenAtRequest == admission.admissionToken,
                admission.reservedRequestCount == 0
            else {
                return
            }

            hasLoadedUsageStats = true
            self.usageStats = stats
        } catch {
            self.error = String(
                format: String(localized: "ai.model.error.loadUsage"),
                locale: AppLocalization.currentLocale,
                error.localizedDescription
            )
        }
    }
    
    func refreshUsageStats() async {
        await loadUsageStats()
    }
    
    func clearError() {
        error = nil
    }
    
    func retryLastQuery() async {
        guard let lastQuery = recentQueries.first,
              lastQuery.error != nil else { return }
        
        await askQuestion(lastQuery.question, category: lastQuery.category)
    }
    
    func clearHistory() async {
        guard let currentUser = Auth.auth().currentUser else { return }
        
        do {
            let db = Firestore.firestore()
            let batch = db.batch()
            
            // Delete all AI queries for the user
            let snapshot = try await db.collection("users")
                .document(currentUser.uid)
                .collection("aiQueries")
                .getDocuments()
            
            for document in snapshot.documents {
                batch.deleteDocument(document.reference)
            }
            
            try await batch.commit()
            
            // Clear local state
            queries.removeAll()
            recentQueries.removeAll()
            
        } catch {
            self.error = String(
                format: String(localized: "ai.model.error.clearHistory"),
                locale: AppLocalization.currentLocale,
                error.localizedDescription
            )
        }
    }
    
    // MARK: - Testing Methods
    #if DEBUG
    /// Puts the given registration where the Firestore queries listener lives, so a test can see
    /// `deinit` remove it without a signed-in user.
    func installQueriesListenerForTesting(_ registration: any ListenerRegistration) {
        queriesListener = registration
    }

    func clearQueriesForTesting() {
        queries.removeAll()
        recentQueries.removeAll()
    }
    
    func setQueriesForTesting(_ testQueries: [AIQuery]) {
        queries = testQueries
        recentQueries = Array(testQueries.prefix(maxRecentQueries))
    }
    
    func setLoadingStateForTesting(_ loading: Bool) {
        isLoading = loading
    }
    
    func setErrorForTesting(_ errorMessage: String?) {
        error = errorMessage
    }
    
    func setUsageStatsForTesting(_ stats: AIUsageStats) {
        admission.revision &+= 1
        admission.synchronizedRevision = admission.revision
        hasLoadedUsageStats = true
        usageStats = stats
    }
    #endif

    // MARK: - Private Methods
    private func loadInitialData() async {
        await performUsageStatsLoad(expectedRevision: 0)
        await loadQueries()
        updateRecentQueries()
    }

    private static func hasCapacity(
        currentCount: Int,
        limit: Int,
        reservations: Int
    ) -> Bool {
        guard currentCount >= 0, limit > currentCount, reservations >= 0 else {
            return false
        }
        return reservations < limit - currentCount
    }
    
    private func updateRecentQueries() {
        // Combine saved queries and current session queries
        let allQueries = queries + recentQueries
        let uniqueQueries = Array(Dictionary(grouping: allQueries, by: \.id).values.compactMap { $0.first })
        
        recentQueries = Array(uniqueQueries.sorted { $0.timestamp > $1.timestamp }.prefix(maxRecentQueries))
    }
    
    private func convertAICategoryToQuestionCategory(_ aiCategory: AICategory) -> String {
        switch aiCategory {
        case .recommendations:
            return "Daily"
        case .advice:
            return "Personal"
        case .learning:
            return "Personal"
        case .travel:
            return "Daily"
        case .productivity:
            return "Goals"
        case .entertainment:
            return "Daily"
        case .creativity:
            return "Creativity"
        case .health:
            return "Health"
        case .career:
            return "Career"
        case .personal:
            return "Personal"
        case .other:
            return "Daily"
        }
    }
    
    private func setupQueriesListener() {
        guard let currentUser = Auth.auth().currentUser else { return }
        
        let db = Firestore.firestore()
        queriesListener = db.collection("users")
            .document(currentUser.uid)
            .collection("aiQueries")
            .order(by: "timestamp", descending: true)
            .addSnapshotListener { [weak self] snapshot, error in
                if let error = error {
                    Task { @MainActor in
                        self?.error = String(
                            format: String(localized: "ai.model.error.syncHistory"),
                            locale: AppLocalization.currentLocale,
                            error.localizedDescription
                        )
                    }
                    return
                }
                
                guard let documents = snapshot?.documents else { return }
                
                let loadedQueries = documents.compactMap { doc in
                    AIQuery.fromFirestore(doc.data(), id: doc.documentID)
                }
                
                Task { @MainActor in
                    self?.queries = loadedQueries
                    self?.updateRecentQueries()
                }
            }
    }
    
    /// `isolated` so the cleanup can read the main-actor listener handles. Below iOS 18.4 the
    /// compiler links a main-actor back-deploy shim, so this needs no deployment-target change.
    isolated deinit {
        queriesListener?.remove()
    }

    /// Bundles the interlocking usage-sync and request-admission bookkeeping that guards
    /// `askQuestion` and `loadUsageStats` against stale completions, listener races, and
    /// concurrent over-admission. Every field is read and mutated only on `AIModel`'s main
    /// actor; the struct carries no isolation of its own and never crosses an actor boundary.
    private struct UsageAdmissionState {
        /// Monotonic counter bumped on every local usage mutation.
        var revision: UInt = 0
        /// Highest `revision` whose persisted write the backend has confirmed.
        var synchronizedRevision: UInt = 0
        /// Rotated when a request is admitted, so a slow reload can detect it raced a submit.
        var admissionToken = UUID()
        /// In-flight requests that have reserved quota but not yet released it.
        var reservedRequestCount = 0
        /// Requests currently running, used to keep `isLoading` truthful.
        var activeRequestCount = 0
        /// True while a usage-stats load is in flight; later callers await it instead of racing.
        var isLoadingStats = true
        /// Callers parked until the in-flight load finishes.
        var loadWaiters: [CheckedContinuation<Void, Never>] = []
        /// The most recently admitted request, so stale completions skip their state writes.
        var latestRequestID: UUID?
        /// Serializes usage persistence so writes apply in submit order.
        var persistenceTask: Task<String?, Never>?
    }
}

// MARK: - Sample Data
extension AIModel {
    static let sample: AIModel = {
        let model = AIModel()
        model.recentQueries = AIQuery.sampleQueries
        // The testing hook exists only in DEBUG; Release still compiles previews that use `sample`.
        #if DEBUG
        model.setUsageStatsForTesting(AIUsageStats.sample)
        #endif
        return model
    }()
}

// MARK: - AI Usage Service
actor AIUsageService: AIUsageServiceProtocol {
    private let db = Firestore.firestore()
    private let userId: String
    
    init(userId: String) {
        self.userId = userId
    }
    
    func getUsageStats() async throws -> AIUsageStats {
        let document = try await db.collection("users")
            .document(userId)
            .collection("aiUsage")
            .document("stats")
            .getDocument()
        
        if let data = document.data(),
           let stats = AIUsageStats.fromFirestore(data) {
            return stats
        }
        
        return AIUsageStats()
    }
    
    func updateUsageStats(_ stats: AIUsageStats) async throws {
        try await db.collection("users")
            .document(userId)
            .collection("aiUsage")
            .document("stats")
            .setData(stats.toFirestore(), merge: true)
    }
    
    func canMakeQuery() async throws -> Bool {
        let stats = try await getUsageStats()
        return stats.canMakeQuery
    }
    
    func incrementQueryCount(category: AICategory) async throws {
        let currentStats = try await getUsageStats()
        let newStats = currentStats.incrementUsage(category: category)
        try await updateUsageStats(newStats)
    }
}
