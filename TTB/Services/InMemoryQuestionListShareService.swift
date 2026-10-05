#if DEBUG
import Foundation

/// In-memory adapter at the question-list-share seam.
///
/// Seeded at construction from owned shares, accepted shares, and recipients-by-share-ID, it
/// reproduces the fixture lifecycle `SharedQuestionListStore`'s local mode implements today —
/// create, preview, accept, disable, regenerate, revoke, leave, reply — without Firebase.
@MainActor
final class InMemoryQuestionListShareService: QuestionListShareServicing {
    private var sharesByID: [String: QuestionListShare]
    private var recipientsByShareID: [String: [QuestionListShareRecipient]]
    /// The adapter's own identity, fixed at construction. `acceptShare(shareCode:actingAs:)`
    /// takes its acting user id as an explicit `actingUserId` parameter rather than rebinding
    /// this, so a local test simulating a different recipient does not permanently change who
    /// this adapter is.
    private let currentUserId: String

    private var ownedSharesOnChange: ((Result<[QuestionListShare], Error>) -> Void)?
    private var acceptedRecipientsOnChange: ((Result<[QuestionListShareRecipient], Error>) -> Void)?

    init(
        ownedShares: [QuestionListShare] = [],
        acceptedShares: [AcceptedQuestionListShare] = [],
        recipientsByShareID: [String: [QuestionListShareRecipient]] = [:],
        currentUserId: String = "local-user"
    ) {
        var shares = Dictionary(uniqueKeysWithValues: ownedShares.map { ($0.id, $0) })
        var recipients = recipientsByShareID
        for acceptedShare in acceptedShares {
            shares[acceptedShare.share.id] = acceptedShare.share
            var shareRecipients = recipients[acceptedShare.share.id] ?? []
            if !shareRecipients.contains(where: { $0.recipientId == acceptedShare.recipient.recipientId }) {
                shareRecipients.append(acceptedShare.recipient)
            }
            recipients[acceptedShare.share.id] = shareRecipients
        }
        sharesByID = shares
        self.recipientsByShareID = recipients
        self.currentUserId = currentUserId
    }

    func ownedSharesListener(
        userId: String,
        completion: @escaping (Result<[QuestionListShare], Error>) -> Void
    ) async -> QuestionListShareListenerHandle {
        ownedSharesOnChange = completion
        publishOwnedShares(for: userId)
        return InMemoryQuestionListShareListenerHandle()
    }

    func acceptedRecipientsListener(
        userId: String,
        completion: @escaping (Result<[QuestionListShareRecipient], Error>) -> Void
    ) async -> QuestionListShareListenerHandle {
        acceptedRecipientsOnChange = completion
        publishAcceptedRecipients(for: userId)
        return InMemoryQuestionListShareListenerHandle()
    }

    func fetchShare(shareId: String) async throws -> QuestionListShare {
        guard let share = sharesByID[shareId] else {
            throw QuestionListShareService.ShareError.invalidResponse
        }
        return share
    }

    func fetchRecipients(shareId: String) async throws -> [QuestionListShareRecipient] {
        recipientsByShareID[shareId] ?? []
    }

    func fetchAcceptedShare(shareId: String, recipientId: String) async throws -> AcceptedQuestionListShare {
        let share = try await fetchShare(shareId: shareId)
        guard let recipient = recipientsByShareID[shareId]?.first(where: { $0.recipientId == recipientId }) else {
            throw QuestionListShareService.ShareError.invalidResponse
        }
        return AcceptedQuestionListShare(share: share, recipient: recipient)
    }

    @discardableResult
    func createShare(listId: String, includeOwnerAnswers: Bool) async throws -> QuestionListShareCreationResult {
        let shareId = UUID().uuidString
        let shareCode = UUID().uuidString
        guard let shareURL = QuestionListShare.shareURL(for: shareCode) else {
            throw QuestionListShareService.ShareError.invalidResponse
        }

        let now = Date()
        let share = QuestionListShare(
            id: shareId,
            ownerId: currentUserId,
            ownerDisplayName: "TTB user",
            sourceListId: listId,
            listName: "Question list",
            questionIds: [],
            includeOwnerAnswers: includeOwnerAnswers,
            ownerAnswerSnapshots: [:],
            shareCode: shareCode,
            recipientCap: QuestionListShare.defaultRecipientCap,
            acceptedRecipientCount: 0,
            status: .active,
            isLinkEnabled: true,
            createdAt: now,
            updatedAt: now
        )
        sharesByID[shareId] = share
        publishOwnedShares(for: currentUserId)

        return QuestionListShareCreationResult(shareId: shareId, shareCode: shareCode, shareURL: shareURL)
    }

    func previewShare(shareCode: String) async throws -> QuestionListSharePreview {
        guard let share = share(withCode: shareCode) else {
            throw QuestionListShareService.ShareError.localShareUnavailable
        }
        let isAccepted = recipientsByShareID[share.id]?.contains {
            $0.recipientId == currentUserId && $0.status == .accepted
        } ?? false

        return QuestionListSharePreview(
            shareId: share.id,
            shareCode: shareCode,
            listName: share.listName,
            ownerDisplayName: share.ownerDisplayName,
            questionCount: share.questionIds.count,
            includeOwnerAnswers: share.includeOwnerAnswers,
            recipientCap: share.recipientCap,
            acceptedRecipientCount: share.acceptedRecipientCount,
            isAccepted: isAccepted
        )
    }

    @discardableResult
    func acceptShare(shareCode: String, actingAs actingUserId: String) async throws -> String {
        guard let share = share(withCode: shareCode) else {
            throw QuestionListShareService.ShareError.localShareUnavailable
        }
        guard share.ownerId != actingUserId else {
            throw QuestionListShareService.ShareError.ownerCannotAccept
        }
        let alreadyAccepted = recipientsByShareID[share.id]?.contains { $0.recipientId == actingUserId } ?? false
        guard share.acceptsNewRecipients || alreadyAccepted else {
            throw QuestionListShareService.ShareError.shareNotAcceptingRecipients
        }

        let now = Date()
        let recipient = QuestionListShareRecipient(
            id: actingUserId,
            shareId: share.id,
            recipientId: actingUserId,
            recipientDisplayName: "TTB user",
            status: .accepted,
            latestReplyAnswerSnapshots: [:],
            repliedAt: nil,
            unreadByOwner: false,
            acceptedAt: now,
            updatedAt: now
        )
        upsertRecipient(recipient, shareId: share.id)
        publishAcceptedRecipients(for: actingUserId)
        return share.id
    }

    func disableShare(shareId: String) async throws {
        try mutateOwnedShare(shareId) { $0.updated(isLinkEnabled: false) }
    }

    func regenerateLink(shareId: String) async throws -> QuestionListShareCreationResult {
        guard let share = sharesByID[shareId] else {
            throw QuestionListShareService.ShareError.invalidResponse
        }
        let shareCode = UUID().uuidString
        guard let shareURL = QuestionListShare.shareURL(for: shareCode) else {
            throw QuestionListShareService.ShareError.invalidResponse
        }
        sharesByID[shareId] = share.updated(shareCode: shareCode, isLinkEnabled: true)
        publishOwnedShares(for: share.ownerId)
        return QuestionListShareCreationResult(shareId: shareId, shareCode: shareCode, shareURL: shareURL)
    }

    func revokeShare(shareId: String) async throws {
        try mutateOwnedShare(shareId) { $0.updated(status: .revoked) }
    }

    func leaveShare(shareId: String) async throws {
        recipientsByShareID[shareId]?.removeAll { $0.recipientId == currentUserId }
        publishAcceptedRecipients(for: currentUserId)
    }

    func sendReply(shareId: String) async throws {
        try updateRecipient(shareId: shareId, recipientId: currentUserId) {
            Self.updatedRecipient($0, repliedAt: Date(), unreadByOwner: true)
        }
    }

    func markReplySeen(shareId: String, recipientId: String) async throws {
        try updateRecipient(shareId: shareId, recipientId: recipientId) {
            Self.updatedRecipient($0, unreadByOwner: false)
        }
    }

    // MARK: - Private

    private func share(withCode shareCode: String) -> QuestionListShare? {
        sharesByID.values.first { $0.shareCode == shareCode }
    }

    private func upsertRecipient(_ recipient: QuestionListShareRecipient, shareId: String) {
        var recipients = recipientsByShareID[shareId] ?? []
        if let index = recipients.firstIndex(where: { $0.recipientId == recipient.recipientId }) {
            recipients[index] = recipient
        } else {
            recipients.append(recipient)
        }
        recipientsByShareID[shareId] = recipients
    }

    private func updateRecipient(
        shareId: String,
        recipientId: String,
        update: (QuestionListShareRecipient) -> QuestionListShareRecipient
    ) throws {
        guard var recipients = recipientsByShareID[shareId],
              let index = recipients.firstIndex(where: { $0.recipientId == recipientId })
        else {
            throw QuestionListShareService.ShareError.invalidResponse
        }
        recipients[index] = update(recipients[index])
        recipientsByShareID[shareId] = recipients
    }

    private func mutateOwnedShare(
        _ shareId: String,
        update: (QuestionListShare) -> QuestionListShare
    ) throws {
        guard let share = sharesByID[shareId] else {
            throw QuestionListShareService.ShareError.invalidResponse
        }
        let updated = update(share)
        sharesByID[shareId] = updated
        publishOwnedShares(for: updated.ownerId)
    }

    private func publishOwnedShares(for userId: String) {
        let shares = sharesByID.values
            .filter { $0.ownerId == userId }
            .sorted { $0.updatedAt > $1.updatedAt }
        ownedSharesOnChange?(.success(shares))
    }

    private func publishAcceptedRecipients(for userId: String) {
        let recipients = recipientsByShareID.values
            .flatMap { $0 }
            .filter { $0.recipientId == userId && $0.status == .accepted }
            .sorted { $0.updatedAt > $1.updatedAt }
        acceptedRecipientsOnChange?(.success(recipients))
    }

    private static func updatedRecipient(
        _ recipient: QuestionListShareRecipient,
        repliedAt: Date? = nil,
        unreadByOwner: Bool
    ) -> QuestionListShareRecipient {
        QuestionListShareRecipient(
            id: recipient.id,
            shareId: recipient.shareId,
            recipientId: recipient.recipientId,
            recipientDisplayName: recipient.recipientDisplayName,
            status: recipient.status,
            latestReplyAnswerSnapshots: recipient.latestReplyAnswerSnapshots,
            repliedAt: repliedAt ?? recipient.repliedAt,
            unreadByOwner: unreadByOwner,
            acceptedAt: recipient.acceptedAt,
            updatedAt: Date()
        )
    }
}

private struct InMemoryQuestionListShareListenerHandle: QuestionListShareListenerHandle {
    func remove() {}
}
#endif
