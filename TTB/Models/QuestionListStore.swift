import FirebaseAuth
import FirebaseFirestore
import Foundation
import os

enum QuestionListStoreError: LocalizedError {
    case localListNotFound(String)
    case permanentAccountRequired
    case sessionChanged

    var errorDescription: String? {
        switch self {
        case .localListNotFound(let listId):
            return "Question list not found: \(listId)"
        case .permanentAccountRequired:
            return String(localized: "questionLists.guest.body")
        case .sessionChanged:
            return "The active account changed before the list operation completed."
        }
    }
}

@MainActor
class QuestionListStore: ObservableObject {
    @Published private(set) var lists: [QuestionList] = []
    @Published private(set) var isLoading = false
    @Published var error: String?

    private let questionListService: (any QuestionListServicing)?
    private var userId: String {
        didSet {
            if oldValue != userId {
                Task { await resetListenerForCurrentUser() }
            }
        }
    }
    private var listener: FirestoreListenerHandle?
    private var listenerGeneration: UInt = 0
    private var authListener: AuthStateDidChangeListenerHandle?
    private var mutationVersions: [String: UInt] = [:]
    private var mutationSequence: UInt = 0
    private var sessionGeneration: UInt = 0
    private var authoritativeSnapshotRevision: UInt = 0
    private var activeRemoteMutationListIDs: Set<String> = []
    private var remoteMutationWaiters: [
        String: [RemoteMutationWaiter]
    ] = [:]
#if DEBUG
    private var remoteMutationQueuedContinuations: [
        String: [CheckedContinuation<Void, Never>]
    ] = [:]
#endif
    private let observesAuth: Bool
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.ttb.app",
        category: "QuestionListStore")

    init(
        questionListService: (any QuestionListServicing)? = QuestionListService(),
        userId: String = "",
        observesAuth: Bool = true,
        startsListener: Bool = true
    ) {
        self.questionListService = questionListService
        self.userId = userId
        self.observesAuth = observesAuth

        if observesAuth {
            setupAuthListener()
        }

        if startsListener, !userId.isEmpty {
            Task { await resetListenerForCurrentUser() }
        }
    }

    init(localLists: [QuestionList]) {
        questionListService = nil
        userId = "local-user"
        observesAuth = false
        lists = localLists.sorted { $0.updatedAt > $1.updatedAt }
    }

    /// `isolated` so the cleanup can read the main-actor listener handles. Below iOS 18.4 the
    /// compiler links a main-actor back-deploy shim, so this needs no deployment-target change.
    isolated deinit {
        listener?.cancel()
        if observesAuth, let authListener {
            Auth.auth().removeStateDidChangeListener(authListener)
        }
    }

    func listsContaining(questionId: String) -> [QuestionList] {
        lists.filter { $0.questionIds.contains(questionId) }
    }

    /// Read a few times per card body, so it answers the question without allocating the array of
    /// matching lists that `listsContaining(questionId:)` builds.
    func isQuestionInAnyList(_ questionId: String) -> Bool {
        lists.contains { $0.questionIds.contains(questionId) }
    }

    func isQuestion(_ questionId: String, in listId: String) -> Bool {
        lists.first(where: { $0.id == listId })?.questionIds.contains(questionId) ?? false
    }

    func questions(in list: QuestionList, using questionModel: QuestionModel) -> [Question] {
        list.questionIds.compactMap { questionModel.question(withID: $0) }
    }

    @discardableResult
    func createList(named name: String) async throws -> QuestionList {
        let normalizedName = Self.normalizedName(name)
        guard let questionListService else {
            let list = QuestionList(
                id: UUID().uuidString,
                ownerId: userId,
                name: normalizedName,
                questionIds: [],
                visibility: "private",
                createdAt: Date(),
                updatedAt: Date()
            )
            lists.insert(list, at: 0)
            return list
        }

        guard !userId.isEmpty else {
            throw QuestionListStoreError.permanentAccountRequired
        }

        let ownerID = userId
        let creationSessionGeneration = sessionGeneration
        let listId = try await questionListService.createList(
            named: normalizedName,
            ownerId: ownerID
        )
        guard
            userId == ownerID,
            sessionGeneration == creationSessionGeneration
        else {
            throw QuestionListStoreError.sessionChanged
        }
        let list = QuestionList(
            id: listId,
            ownerId: ownerID,
            name: normalizedName,
            questionIds: [],
            visibility: "private",
            createdAt: Date(),
            updatedAt: Date()
        )
        upsert(list)
        return list
    }

    func updateList(_ list: QuestionList, name: String) async throws {
        let normalizedName = Self.normalizedName(name)
        guard lists.contains(where: { $0.id == list.id }) else {
            throw QuestionListStoreError.localListNotFound(list.id)
        }
        try await withRemoteMutationSlot(for: list.id) {
            guard let previousList = lists.first(where: { $0.id == list.id }) else {
                throw QuestionListStoreError.localListNotFound(list.id)
            }
            let mutation = beginMutation(for: list.id)
            updateLocalList(list.id) { localList in
                localList.name = normalizedName
                localList.updatedAt = Date()
            }

            do {
                try await questionListService?.updateList(
                    listId: list.id,
                    name: normalizedName
                )
            } catch {
                restore(previousList, for: mutation)
                publish(error: error, for: mutation)
                throw error
            }
        }
    }

    func deleteList(_ list: QuestionList) async throws {
        guard lists.contains(where: { $0.id == list.id }) else {
            throw QuestionListStoreError.localListNotFound(list.id)
        }
        try await withRemoteMutationSlot(for: list.id) {
            guard let previousList = lists.first(where: { $0.id == list.id }) else {
                throw QuestionListStoreError.localListNotFound(list.id)
            }
            let mutation = beginMutation(for: list.id)
            lists.removeAll { $0.id == list.id }

            do {
                try await questionListService?.deleteList(listId: list.id)
            } catch {
                restore(previousList, for: mutation)
                publish(error: error, for: mutation)
                throw error
            }
        }
    }

    func setQuestion(_ questionId: String, in list: QuestionList, isIncluded: Bool) async throws {
        guard lists.contains(where: { $0.id == list.id }) else {
            throw QuestionListStoreError.localListNotFound(list.id)
        }
        try await withRemoteMutationSlot(for: list.id) {
            guard let previousList = lists.first(where: { $0.id == list.id }) else {
                throw QuestionListStoreError.localListNotFound(list.id)
            }
            let mutation = beginMutation(for: list.id)
            updateLocalList(list.id) { localList in
                if isIncluded {
                    if !localList.questionIds.contains(questionId) {
                        localList.questionIds.append(questionId)
                    }
                } else {
                    localList.questionIds.removeAll { $0 == questionId }
                }
                localList.updatedAt = Date()
            }

            do {
                try await questionListService?.setQuestion(
                    questionId,
                    in: list.id,
                    isIncluded: isIncluded
                )
            } catch {
                restore(previousList, for: mutation)
                publish(error: error, for: mutation)
                throw error
            }
        }
    }

    #if DEBUG
    func applyListenerSnapshotForTesting(_ lists: [QuestionList]) {
        applyAuthoritativeSnapshot(lists)
    }

    /// Puts the given handle where the Firestore listener lives, so a test can see `deinit`
    /// cancel it without a signed-in user or a live `QuestionListService`.
    func installListenerForTesting(_ handle: FirestoreListenerHandle) {
        listener = handle
    }
    #endif

    private func setupAuthListener() {
        authListener = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            guard let self else { return }
            Task { @MainActor in
                let newUserId = user?.isAnonymous == true ? "" : user?.uid ?? ""
                self.transitionToUser(withID: newUserId)
            }
        }
    }

    func transitionToUser(withID newUserId: String) {
        guard newUserId != userId else { return }
        sessionGeneration &+= 1
        invalidateRemoteMutationWaiters()
        mutationSequence &+= 1
        mutationVersions.removeAll()
        lists = []
        error = nil
        isLoading = false
        userId = newUserId
    }

    private func resetListenerForCurrentUser() async {
        listenerGeneration &+= 1
        let generation = listenerGeneration
        listener?.cancel()
        listener = nil

        guard !userId.isEmpty, let questionListService else {
            lists = []
            isLoading = false
            return
        }

        isLoading = true
        error = nil
        let listenerUserId = userId
        let newListener = await questionListService.setupQuestionListsListener(
            userId: listenerUserId
        ) { [weak self] result in
            guard
                let self,
                listenerGeneration == generation,
                userId == listenerUserId
            else {
                return
            }
            switch result {
            case .success(let lists):
                applyAuthoritativeSnapshot(lists)
                error = nil
            case .failure(let error):
                self.error = error.localizedDescription
                logger.error("Question list snapshot failed: \(error.localizedDescription)")
            }
            isLoading = false
        }

        guard
            listenerGeneration == generation,
            userId == listenerUserId
        else {
            newListener.cancel()
            return
        }
        listener = newListener
    }

    private func upsert(_ list: QuestionList) {
        if let index = lists.firstIndex(where: { $0.id == list.id }) {
            lists[index] = list
        } else {
            lists.insert(list, at: 0)
        }
        lists.sort { $0.updatedAt > $1.updatedAt }
    }

    private func updateLocalList(_ listId: String, transform: (inout QuestionList) -> Void) {
        guard let index = lists.firstIndex(where: { $0.id == listId }) else { return }
        transform(&lists[index])
        lists.sort { $0.updatedAt > $1.updatedAt }
    }

    private func applyAuthoritativeSnapshot(_ lists: [QuestionList]) {
        authoritativeSnapshotRevision &+= 1
        self.lists = lists.sorted { $0.updatedAt > $1.updatedAt }
    }

    private func beginMutation(for listId: String) -> MutationToken {
        let version = (mutationVersions[listId] ?? 0) &+ 1
        mutationVersions[listId] = version
        mutationSequence &+= 1
        error = nil
        return MutationToken(
            listID: listId,
            userID: userId,
            sessionGeneration: sessionGeneration,
            listVersion: version,
            sequence: mutationSequence,
            authoritativeSnapshotRevision: authoritativeSnapshotRevision
        )
    }

    private func withRemoteMutationSlot(
        for listID: String,
        operation: () async throws -> Void
    ) async throws {
        let session = MutationSession(
            userID: userId,
            generation: sessionGeneration
        )
        let acquired = await acquireRemoteMutationSlot(
            for: listID,
            session: session
        )
        guard acquired else {
            throw QuestionListStoreError.sessionChanged
        }

        defer { releaseRemoteMutationSlot(for: listID) }
        try Task.checkCancellation()
        guard isCurrentSession(session) else {
            throw QuestionListStoreError.sessionChanged
        }
        try await operation()
        guard isCurrentSession(session) else {
            throw QuestionListStoreError.sessionChanged
        }
    }

    private func acquireRemoteMutationSlot(
        for listID: String,
        session: MutationSession
    ) async -> Bool {
        guard activeRemoteMutationListIDs.contains(listID) else {
            activeRemoteMutationListIDs.insert(listID)
            return true
        }

        return await withCheckedContinuation { continuation in
            remoteMutationWaiters[listID, default: []].append(
                RemoteMutationWaiter(
                    session: session,
                    continuation: continuation
                )
            )
#if DEBUG
            let queuedContinuations =
                remoteMutationQueuedContinuations.removeValue(forKey: listID) ?? []
            queuedContinuations.forEach { $0.resume() }
#endif
        }
    }

    private func releaseRemoteMutationSlot(for listID: String) {
        guard var waiters = remoteMutationWaiters[listID], !waiters.isEmpty else {
            activeRemoteMutationListIDs.remove(listID)
            remoteMutationWaiters[listID] = nil
            return
        }

        let next = waiters.removeFirst()
        remoteMutationWaiters[listID] = waiters.isEmpty ? nil : waiters
        next.continuation.resume(returning: true)
    }

    private func invalidateRemoteMutationWaiters() {
        let waiters = remoteMutationWaiters.values.flatMap { $0 }
        remoteMutationWaiters.removeAll()
        waiters.forEach { $0.continuation.resume(returning: false) }
    }

    private func restore(
        _ previousList: QuestionList,
        for mutation: MutationToken
    ) {
        guard
            isCurrentSession(for: mutation),
            mutationVersions[mutation.listID] == mutation.listVersion,
            authoritativeSnapshotRevision == mutation.authoritativeSnapshotRevision
        else {
            return
        }

        upsert(previousList)
    }

    private func publish(error mutationError: Error, for mutation: MutationToken) {
        guard
            isCurrentSession(for: mutation),
            mutation.sequence == mutationSequence
        else {
            return
        }

        error = mutationError.localizedDescription
    }

    private func isCurrentSession(for mutation: MutationToken) -> Bool {
        mutation.userID == userId
            && mutation.sessionGeneration == sessionGeneration
    }

    private func isCurrentSession(_ session: MutationSession) -> Bool {
        session.userID == userId
            && session.generation == sessionGeneration
    }

#if DEBUG
    func waitUntilRemoteMutationIsQueuedForTesting(for listID: String) async {
        guard remoteMutationWaiters[listID]?.isEmpty != false else { return }
        await withCheckedContinuation { continuation in
            remoteMutationQueuedContinuations[listID, default: []].append(continuation)
        }
    }
#endif

    private static func normalizedName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return String(trimmed.prefix(80))
    }
}

private struct MutationToken {
    let listID: String
    let userID: String
    let sessionGeneration: UInt
    let listVersion: UInt
    let sequence: UInt
    let authoritativeSnapshotRevision: UInt
}

private struct MutationSession {
    let userID: String
    let generation: UInt
}

private struct RemoteMutationWaiter {
    let session: MutationSession
    let continuation: CheckedContinuation<Bool, Never>
}
