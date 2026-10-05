import XCTest
@testable import TTB

@MainActor
final class InMemoryQuestionListShareServiceTests: XCTestCase {
    func testCreateShareAddsOwnedShareForCurrentUser() async throws {
        let service = InMemoryQuestionListShareService(currentUserId: "owner")

        let result = try await service.createShare(listId: "list-1", includeOwnerAnswers: true)

        let share = try await service.fetchShare(shareId: result.shareId)
        XCTAssertEqual(share.ownerId, "owner")
        XCTAssertEqual(share.sourceListId, "list-1")
        XCTAssertEqual(share.shareCode, result.shareCode)
        XCTAssertTrue(share.isLinkEnabled)
        XCTAssertEqual(share.status, .active)
    }

    func testPreviewShareReflectsAcceptanceForCurrentUser() async throws {
        let share = makeShare(id: "share-1", shareCode: "code-1")
        let service = InMemoryQuestionListShareService(ownedShares: [share], currentUserId: "recipient")

        let preview = try await service.previewShare(shareCode: "code-1")
        XCTAssertEqual(preview.shareId, "share-1")
        XCTAssertFalse(preview.isAccepted)

        _ = try await service.acceptShare(shareCode: "code-1", actingAs: "recipient")
        let previewAfterAccept = try await service.previewShare(shareCode: "code-1")
        XCTAssertTrue(previewAfterAccept.isAccepted)
    }

    func testAcceptShareUpsertsRecipient() async throws {
        let share = makeShare(id: "share-1", shareCode: "code-1")
        let service = InMemoryQuestionListShareService(ownedShares: [share], currentUserId: "recipient")

        let shareId = try await service.acceptShare(shareCode: "code-1", actingAs: "recipient")
        XCTAssertEqual(shareId, "share-1")

        let accepted = try await service.fetchAcceptedShare(shareId: shareId, recipientId: "recipient")
        XCTAssertEqual(accepted.recipient.recipientId, "recipient")
        XCTAssertEqual(accepted.recipient.status, .accepted)

        // Accepting again must not add a second recipient row.
        _ = try await service.acceptShare(shareCode: "code-1", actingAs: "recipient")
        let recipients = try await service.fetchRecipients(shareId: shareId)
        XCTAssertEqual(recipients.count, 1)
    }

    func testAcceptShareRejectsOwner() async throws {
        let share = makeShare(id: "share-1", shareCode: "code-1")
        let service = InMemoryQuestionListShareService(ownedShares: [share], currentUserId: "owner")

        await XCTAssertThrowsErrorAsync(
            try await service.acceptShare(shareCode: "code-1", actingAs: "owner")
        ) { error in
            guard case .some(.ownerCannotAccept) = error as? QuestionListShareService.ShareError else {
                return XCTFail("Expected ownerCannotAccept, got \(error)")
            }
        }
    }

    func testAcceptShareRejectsWhenNotAcceptingNewRecipients() async throws {
        let share = makeShare(id: "share-1", shareCode: "code-1", isLinkEnabled: false)
        let service = InMemoryQuestionListShareService(ownedShares: [share], currentUserId: "recipient")

        await XCTAssertThrowsErrorAsync(
            try await service.acceptShare(shareCode: "code-1", actingAs: "recipient")
        ) { error in
            guard case .some(.shareNotAcceptingRecipients) = error as? QuestionListShareService.ShareError else {
                return XCTFail("Expected shareNotAcceptingRecipients, got \(error)")
            }
        }
    }

    func testAcceptShareUnknownCodeThrowsLocalShareUnavailable() async {
        let service = InMemoryQuestionListShareService(currentUserId: "recipient")

        await XCTAssertThrowsErrorAsync(
            try await service.acceptShare(shareCode: "missing", actingAs: "recipient")
        ) { error in
            guard case .some(.localShareUnavailable) = error as? QuestionListShareService.ShareError else {
                return XCTFail("Expected localShareUnavailable, got \(error)")
            }
        }
    }

    func testDisableShareTurnsOffLinkWithoutChangingCode() async throws {
        let share = makeShare(id: "share-1", shareCode: "code-1")
        let service = InMemoryQuestionListShareService(ownedShares: [share], currentUserId: "owner")

        try await service.disableShare(shareId: "share-1")

        let updated = try await service.fetchShare(shareId: "share-1")
        XCTAssertFalse(updated.isLinkEnabled)
        XCTAssertEqual(updated.shareCode, "code-1")
    }

    func testRegenerateLinkIssuesNewCodeAndReenablesLink() async throws {
        let share = makeShare(id: "share-1", shareCode: "old-code", isLinkEnabled: false)
        let service = InMemoryQuestionListShareService(ownedShares: [share], currentUserId: "owner")

        let result = try await service.regenerateLink(shareId: "share-1")

        XCTAssertNotEqual(result.shareCode, "old-code")
        let updated = try await service.fetchShare(shareId: "share-1")
        XCTAssertEqual(updated.shareCode, result.shareCode)
        XCTAssertTrue(updated.isLinkEnabled)
    }

    func testRevokeShareSetsRevokedStatus() async throws {
        let share = makeShare(id: "share-1", shareCode: "code-1")
        let service = InMemoryQuestionListShareService(ownedShares: [share], currentUserId: "owner")

        try await service.revokeShare(shareId: "share-1")

        let updated = try await service.fetchShare(shareId: "share-1")
        XCTAssertEqual(updated.status, .revoked)
    }

    func testLeaveShareRemovesCurrentUserAsRecipient() async throws {
        let share = makeShare(id: "share-1", shareCode: "code-1")
        let recipient = makeRecipient(shareId: "share-1", recipientId: "recipient")
        let service = InMemoryQuestionListShareService(
            ownedShares: [share],
            recipientsByShareID: ["share-1": [recipient]],
            currentUserId: "recipient"
        )

        try await service.leaveShare(shareId: "share-1")

        let remaining = try await service.fetchRecipients(shareId: "share-1")
        XCTAssertTrue(remaining.isEmpty)
    }

    func testSendReplyMarksRecipientRepliedAndUnreadByOwner() async throws {
        let share = makeShare(id: "share-1", shareCode: "code-1")
        let recipient = makeRecipient(shareId: "share-1", recipientId: "recipient")
        let service = InMemoryQuestionListShareService(
            ownedShares: [share],
            recipientsByShareID: ["share-1": [recipient]],
            currentUserId: "recipient"
        )

        try await service.sendReply(shareId: "share-1")

        let recipients = try await service.fetchRecipients(shareId: "share-1")
        XCTAssertEqual(recipients.first?.unreadByOwner, true)
        XCTAssertNotNil(recipients.first?.repliedAt)
    }

    func testMarkReplySeenClearsUnreadByOwnerForGivenRecipient() async throws {
        let share = makeShare(id: "share-1", shareCode: "code-1")
        let recipient = makeRecipient(shareId: "share-1", recipientId: "recipient", unreadByOwner: true)
        let service = InMemoryQuestionListShareService(
            ownedShares: [share],
            recipientsByShareID: ["share-1": [recipient]],
            currentUserId: "owner"
        )

        try await service.markReplySeen(shareId: "share-1", recipientId: "recipient")

        let recipients = try await service.fetchRecipients(shareId: "share-1")
        XCTAssertEqual(recipients.first?.unreadByOwner, false)
    }

    func testSeededAcceptedSharesAreVisibleToFetches() async throws {
        let share = makeShare(id: "share-1", shareCode: "code-1")
        let recipient = makeRecipient(shareId: "share-1", recipientId: "recipient")
        let service = InMemoryQuestionListShareService(
            acceptedShares: [AcceptedQuestionListShare(share: share, recipient: recipient)],
            currentUserId: "recipient"
        )

        let accepted = try await service.fetchAcceptedShare(shareId: "share-1", recipientId: "recipient")
        XCTAssertEqual(accepted.share.id, "share-1")
        XCTAssertEqual(accepted.recipient.recipientId, "recipient")
    }

    func testOwnedSharesListenerPublishesOnlyCurrentUsersShares() async {
        let mine = makeShare(id: "mine", shareCode: "code-mine")
        let theirs = QuestionListShare(
            id: "theirs",
            ownerId: "someone-else",
            ownerDisplayName: "Someone",
            sourceListId: "list-2",
            listName: "Theirs",
            questionIds: [],
            includeOwnerAnswers: false,
            ownerAnswerSnapshots: [:],
            shareCode: "code-theirs",
            recipientCap: QuestionListShare.defaultRecipientCap,
            acceptedRecipientCount: 0,
            status: .active,
            isLinkEnabled: true,
            createdAt: Date(),
            updatedAt: Date()
        )
        let service = InMemoryQuestionListShareService(ownedShares: [mine, theirs], currentUserId: "owner")

        var received: [QuestionListShare] = []
        _ = await service.ownedSharesListener(userId: "owner") { result in
            if case .success(let shares) = result {
                received = shares
            }
        }

        XCTAssertEqual(received.map(\.id), ["mine"])
    }

    // MARK: - Helpers

    private func makeShare(
        id: String,
        shareCode: String,
        isLinkEnabled: Bool = true
    ) -> QuestionListShare {
        QuestionListShare(
            id: id,
            ownerId: "owner",
            ownerDisplayName: "Owner",
            sourceListId: "list-1",
            listName: "List \(id)",
            questionIds: ["q1"],
            includeOwnerAnswers: false,
            ownerAnswerSnapshots: [:],
            shareCode: shareCode,
            recipientCap: QuestionListShare.defaultRecipientCap,
            acceptedRecipientCount: 0,
            status: .active,
            isLinkEnabled: isLinkEnabled,
            createdAt: Date(),
            updatedAt: Date()
        )
    }

    private func makeRecipient(
        shareId: String,
        recipientId: String,
        unreadByOwner: Bool = false
    ) -> QuestionListShareRecipient {
        QuestionListShareRecipient(
            id: recipientId,
            shareId: shareId,
            recipientId: recipientId,
            recipientDisplayName: "Recipient",
            status: .accepted,
            latestReplyAnswerSnapshots: [:],
            repliedAt: nil,
            unreadByOwner: unreadByOwner,
            acceptedAt: Date(),
            updatedAt: Date()
        )
    }
}

/// `XCTAssertThrowsError` has no async overload, so this awaits the expression before asserting.
func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    _ errorHandler: (Error) -> Void = { _ in },
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        _ = try await expression()
        XCTFail("Expected an error to be thrown", file: file, line: line)
    } catch {
        errorHandler(error)
    }
}
