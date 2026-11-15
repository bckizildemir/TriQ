import SwiftUI
import FirebaseFirestore
import FirebaseAuth

@MainActor
class BadgeModel: ObservableObject {
    @Published private(set) var badges: [Badge] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorState = ErrorState()
    
    // MARK: - Badge Progress
    @Published private(set) var unlockedBadges: Set<String> = []
    @Published private(set) var badgeProgress: [String: Double] = [:]
    @Published var newlyUnlockedBadge: Badge?
    
    private let store: BadgeStoring
    private var userListener: BadgeUserListening?

    init(store: BadgeStoring = LiveBadgeStore()) {
        self.store = store
    }

    #if DEBUG
    /// A test-only window onto the injected seam. Every store-reaching method here guards on the
    /// global `Auth.auth().currentUser`, which no unit test signs in, so a behavioral test cannot
    /// reach the store through the public surface. This lets a harness test prove that
    /// `AppEnvironment.uiTest` wired the inert store rather than a live Firestore one — FIX-6's
    /// acceptance criterion. Not compiled into a release build.
    var storeForTesting: BadgeStoring { store }

    /// Puts the given handle where the user-document listener lives, so a test can see `deinit`
    /// remove it without a signed-in user.
    func installUserListenerForTesting(_ listener: any BadgeUserListening) {
        userListener = listener
    }
    #endif

    private struct BadgeDefinition: Decodable {
        let id: String
        let title: String
        let description: String
        let icon: String
        let requirement: String
        let titleLocalizations: [String: String]?
        let descriptionLocalizations: [String: String]?
        let requirementLocalizations: [String: String]?
        let targetCount: Int
        let type: String
        let category: String?

        var badgeType: BadgeType {
            BadgeType(rawValue: type) ?? .total
        }
    }

    private nonisolated func defaultBadgeUserFields() -> [String: Any] {
        [
            "dailyAnswers": 0,
            "weeklyAnswers": 0,
            "totalAnswered": 0,
            "completedQuestionIds": [String](),
            "categoryAnswers": [String: Int](),
            "currentStreak": 0,
            "unlockedBadges": [String](),
            "badgeProgress": [String: Double]()
        ]
    }

    private func ensureBadgeUserDocument(userId: String) async throws {
        let (exists, data) = try await store.getUserDocument(userId: userId)
        if !exists {
            var initialData = defaultBadgeUserFields()
            initialData["updatedAt"] = FieldValue.serverTimestamp()
            try await store.setUserDocument(userId: userId, data: initialData, merge: true)
            return
        }

        var patch: [String: Any] = [:]
        for (key, value) in defaultBadgeUserFields() where data[key] == nil {
            patch[key] = value
        }

        if !patch.isEmpty {
            patch["updatedAt"] = FieldValue.serverTimestamp()
            try await store.setUserDocument(userId: userId, data: patch, merge: true)
        }
    }

    private func loadBundledBadgeDefinitions() -> [BadgeDefinition] {
        guard let url = Bundle.main.url(forResource: "BadgeDefinitions", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let defs = try? JSONDecoder().decode([BadgeDefinition].self, from: data) else {
            return []
        }
        return defs
    }

    private func fetchBadgeDefinitions() async throws -> [BadgeDefinition] {
        let documents = try await store.getBadgeDefinitionDocuments()
        let remote: [BadgeDefinition] = documents.compactMap { id, data in
            guard let title = data["title"] as? String,
                  let description = data["description"] as? String,
                  let icon = data["icon"] as? String,
                  let requirement = data["requirement"] as? String else {
                return nil
            }
            return BadgeDefinition(
                id: id,
                title: title,
                description: description,
                icon: icon,
                requirement: requirement,
                titleLocalizations: Self.localizedMap(from: data["titleLocalizations"]),
                descriptionLocalizations: Self.localizedMap(from: data["descriptionLocalizations"]),
                requirementLocalizations: Self.localizedMap(from: data["requirementLocalizations"]),
                targetCount: data["targetCount"] as? Int ?? 0,
                type: data["type"] as? String ?? "total",
                category: data["category"] as? String
            )
        }

        if !remote.isEmpty { return remote }
        return loadBundledBadgeDefinitions()
    }

    nonisolated private static func doubleMap(from value: Any?) -> [String: Double] {
        if let typed = value as? [String: Double] { return typed }
        guard let raw = value as? [String: Any] else { return [:] }
        var result: [String: Double] = [:]
        for (key, item) in raw {
            if let doubleValue = item as? Double {
                result[key] = doubleValue
            } else if let intValue = item as? Int {
                result[key] = Double(intValue)
            } else if let number = item as? NSNumber {
                result[key] = number.doubleValue
            }
        }
        return result
    }
    
    // MARK: - Badge Loading
    func loadBadges() {
        guard let userId = Auth.auth().currentUser?.uid else {
            badges = []
            unlockedBadges = []
            badgeProgress = [:]
            isLoading = false
            return
        }

        guard Auth.auth().currentUser?.isAnonymous == false else {
            userListener?.remove()
            badges = []
            unlockedBadges = []
            badgeProgress = [:]
            newlyUnlockedBadge = nil
            isLoading = false
            return
        }
        
        isLoading = true
        
        // Cancel any existing listener
        userListener?.remove()

        // The listener closure below outlives this task and keeps its own `[weak self]`, so the
        // model does not own a closure that owns the model. Capture weakly here as well: the
        // compiler flags a weak inner capture under an implicit strong outer one.
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await ensureBadgeUserDocument(userId: userId)
            } catch {
                showError(
                    String(
                        format: String(localized: "badge.error.load"),
                        locale: AppLocalization.currentLocale,
                        error.localizedDescription
                    )
                )
                isLoading = false
                return
            }

            // Listen for user document changes
            userListener = store.observeUserDocument(userId: userId) { [weak self] result in
                guard let self = self else { return }

                let userData: [String: Any]
                switch result {
                case .failure(let error):
                    self.showError(
                        String(
                            format: String(localized: "badge.error.load"),
                            locale: AppLocalization.currentLocale,
                            error.localizedDescription
                        )
                    )
                    self.isLoading = false
                    return
                case .success(let data):
                    userData = data ?? [:]
                }

                // Get current user's unlocked badges and progress
                let unlockedBadges = Set(userData["unlockedBadges"] as? [String] ?? [])
                let badgeProgress = Self.doubleMap(from: userData["badgeProgress"])

                // Load all badges and update their status
                Task {
                    do {
                        let defs = try await self.fetchBadgeDefinitions()
                        let badges = defs.map { def in
                            Badge(
                                id: def.id,
                                title: def.title,
                                description: def.description,
                                icon: def.icon,
                                isLocked: !unlockedBadges.contains(def.id),
                                requirement: def.requirement,
                                progress: badgeProgress[def.id] ?? 0.0,
                                targetCount: def.targetCount,
                                type: def.badgeType,
                                category: def.category,
                                titleLocalizations: def.titleLocalizations ?? [:],
                                descriptionLocalizations: def.descriptionLocalizations ?? [:],
                                requirementLocalizations: def.requirementLocalizations ?? [:]
                            )
                        }

                        self.badges = badges
                        self.unlockedBadges = unlockedBadges
                        self.badgeProgress = badgeProgress
                        self.isLoading = false
                    } catch {
                        self.showError(
                            String(
                                format: String(localized: "badge.error.load"),
                                locale: AppLocalization.currentLocale,
                                error.localizedDescription
                            )
                        )
                        self.isLoading = false
                    }
                }
            }
        }
    }
    
    /// `isolated` so the cleanup can read the main-actor listener handles. Below iOS 18.4 the
    /// compiler links a main-actor back-deploy shim, so this needs no deployment-target change.
    isolated deinit {
        userListener?.remove()
    }
    
    // MARK: - Error Handling
    private func showError(_ message: String) {
        errorState.message = message
        errorState.isShowing = true
    }

    private static func localizedMap(from value: Any?) -> [String: String]? {
        if let typed = value as? [String: String] {
            return typed
        }

        guard let raw = value as? [String: Any] else {
            return nil
        }

        var parsed: [String: String] = [:]
        for (key, item) in raw {
            if let stringValue = item as? String {
                parsed[key] = stringValue
            }
        }
        return parsed.isEmpty ? nil : parsed
    }
    
    func dismissError() {
        errorState.isShowing = false
        errorState.message = ""
    }
}
