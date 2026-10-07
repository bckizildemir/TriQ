import FirebaseAuth
import Foundation
import os

@MainActor
final class SharedQuestionListStore: ObservableObject {
    /// Optimistic-insert default for `createShare`'s locally-constructed `QuestionListShare`,
    /// pending the Firestore document the live path actually writes.
    private static let placeholderOwnerDisplayName = "TTB user"

    @Published private(set) var ownedShares: [QuestionListShare] = []
    @Published private(set) var acceptedShares: [AcceptedQuestionListShare] = []
    @Published private(set) var recipientsByShareID: [String: [QuestionListShareRecipient]] = [:]
    @Published private(set) var isLoading = false
    @Published var error: String?

    private let service: QuestionListShareServicing
    private var userId: String {
        didSet {
            if oldValue != userId {
                scheduleListenerReset()
            }
        }
    }
    private let observesAuth: Bool
    /// Whether this instance ever registers a Firestore listener. `false` only for the local/
    /// fixture mode (see the `local*` convenience initializer): that mode has nothing to correct
    /// an optimistic insert later, so `createShare` needs to know which mode it's in.
    private let startsListeners: Bool
    private var ownedSharesListener: QuestionListShareListenerHandle?
    private var acceptedRecipientsListener: QuestionListShareListenerHandle?
    private var authListener: AuthStateDidChangeListenerHandle?
    private var listenerResetTask: Task<Void, Never>?
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.ttb.app",
        category: "SharedQuestionListStore")

    init(
        service: QuestionListShareServicing = QuestionListShareService(),
        userId: String = "",
        observesAuth: Bool = true,
        startsListeners: Bool = true
    ) {
        self.service = service
        self.userId = userId
        self.observesAuth = observesAuth
        self.startsListeners = startsListeners

        if observesAuth {
            setupAuthListener()
        }

        if startsListeners, !userId.isEmpty {
            scheduleListenerReset()
        }
    }

    /// Seeds an in-memory adapter from the given fixtures and delegates to the primary
    /// initializer's field-assignment/auth-listener wiring, then overlays the published state
    /// with the exact snapshot the fixtures describe. `startsListeners` is `false` on this path,
    /// so the in-memory adapter's own listener publish never runs on its own — this overlay is
    /// the only thing that populates `ownedShares`/`acceptedShares`/`recipientsByShareID` for a
    /// fixture-backed store.
    convenience init(
        localOwnedShares: [QuestionListShare],
        localAcceptedShares: [AcceptedQuestionListShare] = [],
        localRecipientsByShareID: [String: [QuestionListShareRecipient]] = [:],
        localUserId: String = "local-user"
    ) {
        #if DEBUG
        let adapter = InMemoryQuestionListShareService(
            ownedShares: localOwnedShares,
            acceptedShares: localAcceptedShares,
            recipientsByShareID: localRecipientsByShareID,
            currentUserId: localUserId
        )
        self.init(
            service: adapter,
            userId: localUserId,
            observesAuth: false,
            startsListeners: false
        )
        ownedShares = localOwnedShares.sorted { $0.updatedAt > $1.updatedAt }
        acceptedShares = localAcceptedShares.sorted { $0.recipient.updatedAt > $1.recipient.updatedAt }
        recipientsByShareID = localRecipientsByShareID
        #else
        self.init(
            service: QuestionListShareService(),
            userId: "",
            observesAuth: true,
            startsListeners: true
        )
        #endif
    }

    /// `isolated` so the cleanup can read the main-actor listener handles. Below iOS 18.4 the
    /// compiler links a main-actor back-deploy shim, so this needs no deployment-target change.
    isolated deinit {
        listenerResetTask?.cancel()
        ownedSharesListener?.remove()
        acceptedRecipientsListener?.remove()
        if observesAuth, let authListener {
            Auth.auth().removeStateDidChangeListener(authListener)
        }
    }

    func ownedShare(withID shareId: String) -> QuestionListShare? {
        ownedShares.first { $0.id == shareId }
    }

    func acceptedShare(withID shareId: String) -> AcceptedQuestionListShare? {
        acceptedShares.first { $0.id == shareId }
    }

    func questions(in share: QuestionListShare, using questionModel: QuestionModel) -> [Question] {
        share.questionIds.compactMap { questionModel.question(withID: $0) }
    }

    @discardableResult
    func createShare(for list: QuestionList, includeOwnerAnswers: Bool) async throws -> QuestionListShareCreationResult {
        do {
            let result = try await service.createShare(
                listId: list.id,
                includeOwnerAnswers: includeOwnerAnswers
            )

            // The live path relies on the Firestore listener to populate `ownedShares` with the
            // real document shortly after. Only local/fixture mode needs the optimistic insert
            // below, since it never gets a listener publish to correct a placeholder with the
            // real owner name.
            guard !startsListeners else {
                return result
            }

            let now = Date()
            let share = QuestionListShare(
                id: result.shareId,
                ownerId: list.ownerId,
                ownerDisplayName: Self.placeholderOwnerDisplayName,
                sourceListId: list.id,
                listName: list.name,
                questionIds: list.questionIds,
                includeOwnerAnswers: includeOwnerAnswers,
                ownerAnswerSnapshots: [:],
                shareCode: result.shareCode,
                recipientCap: QuestionListShare.defaultRecipientCap,
                acceptedRecipientCount: 0,
                status: .active,
                isLinkEnabled: true,
                createdAt: now,
                updatedAt: now
            )
            ownedShares.insert(share, at: 0)
            ownedShares.sort { $0.updatedAt > $1.updatedAt }

            return result
        } catch {
            self.error = error.localizedDescription
            throw error
        }
    }

    func previewShare(shareCode: String) async throws -> QuestionListSharePreview {
        do {
            return try await service.previewShare(shareCode: shareCode)
        } catch {
            self.error = error.localizedDescription
            throw error
        }
    }

    @discardableResult
    func acceptShare(shareCode: String, currentUserId: String?) async throws -> String {
        guard let currentUserId, !currentUserId.isEmpty else {
            throw QuestionListShareService.ShareError.missingUser
        }

        do {
            let shareId = try await service.acceptShare(shareCode: shareCode, actingAs: currentUserId)
            let acceptedShare = try await service.fetchAcceptedShare(
                shareId: shareId,
                recipientId: currentUserId
            )
            upsertAcceptedShare(acceptedShare)
            return shareId
        } catch {
            self.error = error.localizedDescription
            throw error
        }
    }

    @discardableResult
    func loadAcceptedShare(shareId: String, currentUserId: String?) async throws -> String {
        guard let currentUserId, !currentUserId.isEmpty else {
            throw QuestionListShareService.ShareError.missingUser
        }

        if acceptedShare(withID: shareId) != nil {
            return shareId
        }

        do {
            let acceptedShare = try await service.fetchAcceptedShare(
                shareId: shareId,
                recipientId: currentUserId
            )
            upsertAcceptedShare(acceptedShare)
            return shareId
        } catch {
            self.error = error.localizedDescription
            throw error
        }
    }

    func fetchRecipients(for shareId: String) async {
        do {
            let recipients = try await service.fetchRecipients(shareId: shareId)
                .sorted { $0.updatedAt > $1.updatedAt }
            recipientsByShareID[shareId] = recipients
        } catch {
            self.error = error.localizedDescription
        }
    }

    func disableLink(for share: QuestionListShare) async throws {
        try await performShareMutation {
            try await service.disableShare(shareId: share.id)
        }
        replaceOwnedShare(share.id) { old in
            old.updated(isLinkEnabled: false)
        }
    }

    @discardableResult
    func regenerateLink(for share: QuestionListShare) async throws -> QuestionListShareCreationResult {
        do {
            let result = try await service.regenerateLink(shareId: share.id)
            replaceOwnedShare(share.id) { old in
                old.updated(shareCode: result.shareCode, isLinkEnabled: true)
            }
            return result
        } catch {
            self.error = error.localizedDescription
            throw error
        }
    }

    func revoke(_ share: QuestionListShare) async throws {
        try await performShareMutation {
            try await service.revokeShare(shareId: share.id)
        }
        replaceOwnedShare(share.id) { old in
            old.updated(status: .revoked)
        }
    }

    func leave(_ acceptedShare: AcceptedQuestionListShare) async throws {
        try await performShareMutation {
            try await service.leaveShare(shareId: acceptedShare.id)
        }
        acceptedShares.removeAll { $0.id == acceptedShare.id }
    }

    func sendReply(for acceptedShare: AcceptedQuestionListShare) async throws {
        try await performShareMutation {
            try await service.sendReply(shareId: acceptedShare.id)
        }
    }

    func markReplySeen(shareId: String, recipientId: String) async {
        do {
            try await service.markReplySeen(shareId: shareId, recipientId: recipientId)
            if var recipients = recipientsByShareID[shareId],
               let index = recipients.firstIndex(where: { $0.recipientId == recipientId }) {
                let old = recipients[index]
                recipients[index] = QuestionListShareRecipient(
                    id: old.id,
                    shareId: old.shareId,
                    recipientId: old.recipientId,
                    recipientDisplayName: old.recipientDisplayName,
                    status: old.status,
                    latestReplyAnswerSnapshots: old.latestReplyAnswerSnapshots,
                    repliedAt: old.repliedAt,
                    unreadByOwner: false,
                    acceptedAt: old.acceptedAt,
                    updatedAt: Date()
                )
                recipientsByShareID[shareId] = recipients
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    #if DEBUG
    func applyOwnedSharesSnapshotForTesting(_ shares: [QuestionListShare]) {
        ownedShares = shares.sorted { $0.updatedAt > $1.updatedAt }
    }

    func applyAcceptedSharesSnapshotForTesting(_ shares: [AcceptedQuestionListShare]) {
        acceptedShares = shares.sorted { $0.recipient.updatedAt > $1.recipient.updatedAt }
    }

    /// Puts the given handles where the share listeners live, so a test can see `deinit` remove
    /// them without a signed-in user or a live `QuestionListShareService`.
    func installListenersForTesting(
        ownedShares: any QuestionListShareListenerHandle,
        acceptedRecipients: any QuestionListShareListenerHandle
    ) {
        ownedSharesListener = ownedShares
        acceptedRecipientsListener = acceptedRecipients
    }
    #endif

    private func setupAuthListener() {
        authListener = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            guard let self else { return }
            Task { @MainActor in
                let newUserId = user?.isAnonymous == true ? "" : user?.uid ?? ""
                if newUserId != self.userId {
                    self.ownedShares = []
                    self.acceptedShares = []
                    self.recipientsByShareID = [:]
                    self.error = nil
                    self.isLoading = false
                }
                self.userId = newUserId
            }
        }
    }

    /// Serializes listener resets. Two rapid user changes must not interleave: the earlier run
    /// suspends while registering a listener, and without serialization it resumes to overwrite the
    /// later run's registration — leaking a listener that keeps publishing the previous user's
    /// shares into `ownedShares`.
    private func scheduleListenerReset() {
        let previousReset = listenerResetTask
        previousReset?.cancel()
        listenerResetTask = Task { @MainActor [weak self] in
            await previousReset?.value
            guard let self, !Task.isCancelled else { return }
            await self.resetListenersForCurrentUser()
        }
    }

    /// True while `candidateUserId` is still the signed-in user. Every suspension point in the
    /// listener path has to re-check this, because the user can change while it is suspended.
    private func isCurrentUser(_ candidateUserId: String) -> Bool {
        userId == candidateUserId
    }

    private func resetListenersForCurrentUser() async {
        let targetUserId = userId

        ownedSharesListener?.remove()
        ownedSharesListener = nil
        acceptedRecipientsListener?.remove()
        acceptedRecipientsListener = nil

        guard !targetUserId.isEmpty else {
            ownedShares = []
            acceptedShares = []
            recipientsByShareID = [:]
            isLoading = false
            return
        }

        isLoading = true
        error = nil

        let ownedListener = await service.ownedSharesListener(userId: targetUserId) { [weak self] result in
            Task { @MainActor in
                guard let self, self.isCurrentUser(targetUserId) else { return }
                switch result {
                case .success(let shares):
                    self.ownedShares = shares.sorted { $0.updatedAt > $1.updatedAt }
                    self.error = nil
                case .failure(let error):
                    self.error = error.localizedDescription
                    self.logger.error("Owned question list shares snapshot failed: \(error.localizedDescription)")
                }
                self.isLoading = false
            }
        }

        guard !Task.isCancelled, isCurrentUser(targetUserId) else {
            ownedListener.remove()
            return
        }
        ownedSharesListener = ownedListener

        let acceptedListener = await service.acceptedRecipientsListener(userId: targetUserId) { [weak self] result in
            Task { @MainActor in
                guard let self, self.isCurrentUser(targetUserId) else { return }
                switch result {
                case .success(let recipients):
                    await self.loadAcceptedShares(for: recipients, expecting: targetUserId)
                    self.error = nil
                case .failure(let error):
                    self.error = error.localizedDescription
                    self.logger.error("Accepted question list shares snapshot failed: \(error.localizedDescription)")
                }
                self.isLoading = false
            }
        }

        guard !Task.isCancelled, isCurrentUser(targetUserId) else {
            acceptedListener.remove()
            return
        }
        acceptedRecipientsListener = acceptedListener
    }

    private func loadAcceptedShares(
        for recipients: [QuestionListShareRecipient],
        expecting targetUserId: String
    ) async {
        var loaded: [AcceptedQuestionListShare] = []
        for recipient in recipients {
            do {
                let share = try await service.fetchShare(shareId: recipient.shareId)
                guard isCurrentUser(targetUserId) else { return }
                guard share.isActive else { continue }
                loaded.append(AcceptedQuestionListShare(share: share, recipient: recipient))
            } catch {
                logger.error("Failed to load accepted share \(recipient.shareId): \(error.localizedDescription)")
            }
        }
        guard isCurrentUser(targetUserId) else { return }
        acceptedShares = loaded.sorted { $0.recipient.updatedAt > $1.recipient.updatedAt }
    }

    private func upsertAcceptedShare(_ acceptedShare: AcceptedQuestionListShare) {
        if let index = acceptedShares.firstIndex(where: { $0.id == acceptedShare.id }) {
            acceptedShares[index] = acceptedShare
        } else {
            acceptedShares.insert(acceptedShare, at: 0)
        }
        acceptedShares.sort { $0.recipient.updatedAt > $1.recipient.updatedAt }
    }

    private func replaceOwnedShare(
        _ shareId: String,
        update: (QuestionListShare) -> QuestionListShare
    ) {
        guard let index = ownedShares.firstIndex(where: { $0.id == shareId }) else { return }
        ownedShares[index] = update(ownedShares[index])
        ownedShares.sort { $0.updatedAt > $1.updatedAt }
    }

    private func performShareMutation(_ operation: () async throws -> Void) async throws {
        do {
            try await operation()
        } catch {
            self.error = error.localizedDescription
            throw error
        }
    }
}
