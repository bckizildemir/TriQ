import XCTest
@testable import TTB

@MainActor
final class QuestionListShareTests: XCTestCase {
    func testShareParsingKeepsTextSnapshotsOnly() {
        let share = QuestionListShare.fromFirestore([
            "ownerId": "owner",
            "ownerDisplayName": "Berke",
            "sourceListId": "list-1",
            "listName": "Friends",
            "questionIds": ["q1", "q2"],
            "includeOwnerAnswers": true,
            "ownerAnswerSnapshots": [
                "q1": [" One ", "", "Three"],
                "q2": ["", "", ""],
            ],
            "imageURLs": [
                "q1": ["https://example.com/private.jpg"],
            ],
            "shareCode": "abc",
            "recipientCap": 25,
            "acceptedRecipientCount": 2,
            "status": "active",
            "isLinkEnabled": true,
        ], id: "share-1")

        XCTAssertEqual(share?.ownerDisplayName, "Berke")
        XCTAssertEqual(share?.ownerTextSnapshot(for: "q1"), ["One", "", "Three"])
        XCTAssertNil(share?.ownerAnswerSnapshots["imageURLs"])
        XCTAssertEqual(share?.recipientCardMode(for: "q1"), .comparison)
        XCTAssertEqual(share?.recipientCardMode(for: "q2"), .answerCard)
        XCTAssertEqual(share?.shareURL?.absoluteString, "https://ttbp-9d652.web.app/share/lists/abc")
    }

    func testMalformedRecipientCountersFailClosed() throws {
        let share = try XCTUnwrap(QuestionListShare.fromFirestore([
            "ownerId": "owner",
            "recipientCap": 0,
            "acceptedRecipientCount": -1,
            "status": "active",
            "isLinkEnabled": true,
        ], id: "corrupted-share"))

        XCTAssertFalse(share.acceptsNewRecipients)
    }

    func testWrongTypeRecipientCountersRejectShare() {
        let malformedFields: [(name: String, value: Any)] = [
            ("recipientCap", "25"),
            ("acceptedRecipientCount", 2.5),
            ("recipientCap", NSNumber(value: true)),
            ("acceptedRecipientCount", NSNumber(value: false)),
            ("recipientCap", NSNumber(value: UInt64.max)),
        ]

        for malformedField in malformedFields {
            XCTAssertNil(
                QuestionListShare.fromFirestore([
                    "ownerId": "owner",
                    "recipientCap": malformedField.name == "recipientCap" ? malformedField.value : 25,
                    "acceptedRecipientCount": malformedField.name == "acceptedRecipientCount"
                        ? malformedField.value
                        : 2,
                ], id: "malformed-\(malformedField.name)"),
                "\(malformedField.name) must not silently fall back when present with the wrong type"
            )
        }
    }

    func testMissingRecipientCountersUseLegacyDefaults() throws {
        let share = try XCTUnwrap(QuestionListShare.fromFirestore([
            "ownerId": "owner",
        ], id: "legacy-share"))

        XCTAssertEqual(share.recipientCap, QuestionListShare.defaultRecipientCap)
        XCTAssertEqual(share.acceptedRecipientCount, 0)
    }

    func testCanonicalShareURLUsesPublicHTTPSLink() {
        XCTAssertEqual(
            QuestionListShare.shareURL(for: "share-code")?.absoluteString,
            "https://ttbp-9d652.web.app/share/lists/share-code"
        )
        XCTAssertEqual(
            QuestionListShare.shareURL(for: "share code")?.absoluteString,
            "https://ttbp-9d652.web.app/share/lists/share%20code"
        )
    }

    func testQuestionListShareErrorMessagesUseExpectedCopy() {
        let ownLinkError = NSError(
            domain: "com.google.firebase.functions",
            code: 0,
            userInfo: [NSLocalizedDescriptionKey: "Owners cannot accept their own share link."]
        )
        XCTAssertEqual(
            QuestionListShareService.userFacingMessage(for: ownLinkError),
            "You cannot accept your own shared list link."
        )

        let disabledLinkError = NSError(
            domain: "com.google.firebase.functions",
            code: 0,
            userInfo: [NSLocalizedDescriptionKey: "This share link is not accepting recipients."]
        )
        XCTAssertEqual(
            QuestionListShareService.userFacingMessage(for: disabledLinkError),
            "This shared list link is no longer accepting recipients."
        )

        let networkError = URLError(.notConnectedToInternet)
        XCTAssertEqual(
            QuestionListShareService.userFacingMessage(for: networkError),
            "The shared list could not be reached. Check your connection and try again."
        )
    }

    func testRecipientParsingUsesLatestReplySnapshot() {
        let recipient = QuestionListShareRecipient.fromFirestore([
            "recipientId": "user-2",
            "recipientDisplayName": "Ada",
            "status": "accepted",
            "latestReplyAnswerSnapshots": [
                "q1": ["New", "Two"],
            ],
            "unreadByOwner": true,
        ], id: "user-2", shareId: "share-1")

        XCTAssertEqual(recipient?.recipientDisplayName, "Ada")
        XCTAssertEqual(recipient?.latestReplyAnswerSnapshots["q1"], ["New", "Two", ""])
        XCTAssertEqual(recipient?.status, .accepted)
        XCTAssertEqual(recipient?.unreadByOwner, true)
    }

    func testListShareDeepLinkRouting() {
        let url = URL(string: "https://ttbp-9d652.web.app/share/lists/share-code")!
        XCTAssertEqual(AppDeepLinkRouter.questionListShareCode(from: url), "share-code")
        XCTAssertNil(AppDeepLinkRouter.questionId(from: url))

        let router = AppDeepLinkRouter()
        router.handle(url)

        XCTAssertEqual(router.sharedQuestionList?.shareCode, "share-code")
        XCTAssertNil(router.sharedQuestion)
    }

    func testQuestionShareDeepLinkRouting() {
        let url = URL(string: "https://ttbp-9d652.web.app/q/question-1")!
        XCTAssertEqual(AppDeepLinkRouter.questionId(from: url), "question-1")
        XCTAssertNil(AppDeepLinkRouter.questionListShareCode(from: url))

        let router = AppDeepLinkRouter()
        router.handle(url)

        XCTAssertEqual(router.sharedQuestion?.questionId, "question-1")
        XCTAssertNil(router.sharedQuestionList)
    }

    func testAcceptedListNavigationRequestCanBeConsumed() throws {
        let router = AppDeepLinkRouter()

        router.requestAcceptedQuestionListShareDetail(shareId: " share-1 ")

        XCTAssertEqual(router.acceptedQuestionListShareDetail?.shareId, "share-1")

        let request = try XCTUnwrap(router.acceptedQuestionListShareDetail)
        router.consumeAcceptedQuestionListShareDetail(request)

        XCTAssertNil(router.acceptedQuestionListShareDetail)
    }

    func testLegacyListShareDeepLinkRouting() {
        let url = URL(string: "https://ttbp-9d652.web.app/l/share-code")!
        XCTAssertEqual(AppDeepLinkRouter.questionListShareCode(from: url), "share-code")
        XCTAssertNil(AppDeepLinkRouter.questionId(from: url))
    }

    func testListShareDeepLinkRoutingDecodesShareCode() {
        let url = URL(string: "https://ttbp-9d652.web.app/share/lists/share%20code")!
        XCTAssertEqual(AppDeepLinkRouter.questionListShareCode(from: url), "share code")
    }

    func testCustomSchemeListShareDeepLinkRouting() {
        let url = URL(string: "ttbp://l/share-code")!
        XCTAssertEqual(AppDeepLinkRouter.questionListShareCode(from: url), "share-code")
        XCTAssertNil(AppDeepLinkRouter.questionId(from: url))
    }

    func testUserHandleFormatterAddsAtSignOnlyWhenNeeded() {
        XCTAssertEqual(UserHandleFormatter.handle("Berke"), "@Berke")
        XCTAssertEqual(UserHandleFormatter.handle("@Ada"), "@Ada")
        XCTAssertEqual(UserHandleFormatter.handle("  "), "@ttb-user")
    }

    func testQuestionListShareActivityPayloadIncludesCopyAndURL() throws {
        let url = try XCTUnwrap(QuestionListShare.shareURL(for: "share-code"))

        let payload = QuestionListShareActivityPayload.make(
            senderDisplayName: "Berke",
            listName: "Friends",
            questionCount: 3,
            url: url
        )

        XCTAssertEqual(
            payload.text,
            "@Berke shared \"Friends\" with 3 questions on TTB.\nhttps://ttbp-9d652.web.app/share/lists/share-code"
        )
        XCTAssertEqual(payload.url, url)
    }

    func testLocalSharedQuestionListStoreSortsShares() {
        let olderShare = makeShare(id: "older", updatedAt: Date(timeIntervalSince1970: 10))
        let newerShare = makeShare(id: "newer", updatedAt: Date(timeIntervalSince1970: 20))
        let store = SharedQuestionListStore(localOwnedShares: [])

        store.applyOwnedSharesSnapshotForTesting([olderShare, newerShare])

        XCTAssertEqual(store.ownedShares.map(\.id), ["newer", "older"])
    }

    func testAcceptedSharesSortByRecipientUpdateTime() {
        let share = makeShare(id: "share")
        let older = AcceptedQuestionListShare(
            share: share,
            recipient: makeRecipient(shareId: share.id, updatedAt: Date(timeIntervalSince1970: 10))
        )
        let newer = AcceptedQuestionListShare(
            share: makeShare(id: "share-2"),
            recipient: makeRecipient(
                shareId: "share-2",
                updatedAt: Date(timeIntervalSince1970: 20)
            )
        )
        let store = SharedQuestionListStore(localOwnedShares: [], localAcceptedShares: [])

        store.applyAcceptedSharesSnapshotForTesting([older, newer])

        XCTAssertEqual(store.acceptedShares.map(\.id), ["share-2", "share"])
    }

    func testLocalCreateShareCreatesOwnedShareWithoutFixtureError() async throws {
        let store = SharedQuestionListStore(localOwnedShares: [])
        let list = makeList(id: "local-list", questionIds: ["q1", "q2"])

        let result = try await store.createShare(for: list, includeOwnerAnswers: true)

        XCTAssertEqual(store.ownedShares.map(\.id), [result.shareId])
        XCTAssertEqual(store.ownedShares.first?.shareCode, result.shareCode)
        XCTAssertEqual(store.ownedShares.first?.questionIds, ["q1", "q2"])
        XCTAssertEqual(
            result.shareURL.absoluteString,
            "https://ttbp-9d652.web.app/share/lists/\(result.shareCode)"
        )
        XCTAssertNotEqual(result.shareCode, "local-share")
    }

    func testLiveCreateShareDoesNotInsertPlaceholderOwnerName() async throws {
        let service = FakeLiveQuestionListShareService()
        // `startsListeners` is deliberately not passed here: production (AppEnvironment.live(),
        // AppEnvironment.swift:150) relies on it defaulting to `true` at the designated
        // initializer, and this test needs to exercise that real default, not a hand-written
        // stand-in for it. `observesAuth: false` is unrelated to what this test checks — it just
        // keeps the test from registering a real Firebase Auth listener.
        let store = SharedQuestionListStore(
            service: service,
            userId: "owner-1",
            observesAuth: false
        )
        let list = makeList(id: "live-list", questionIds: ["q1"])

        let result = try await store.createShare(for: list, includeOwnerAnswers: true)

        // The live path leaves ownedShares for the Firestore listener to populate with the real
        // document; it must not optimistically insert a "TTB user"-named placeholder the way the
        // local/fixture path does.
        XCTAssertNil(store.ownedShare(withID: result.shareId))
    }

    func testAcceptShareDoesNotPermanentlyRebindAdapterIdentity() async throws {
        let share = makeShare(id: "share-1", shareCode: "code-1")
        let service = InMemoryQuestionListShareService(ownedShares: [share], currentUserId: "local-user")

        _ = try await service.acceptShare(shareCode: "code-1", actingAs: "recipient-B")

        // A later call must still run as the adapter's own construction-time identity, not as
        // whoever last accepted a share through it.
        let result = try await service.createShare(listId: "list-1", includeOwnerAnswers: true)
        let created = try await service.fetchShare(shareId: result.shareId)
        XCTAssertEqual(created.ownerId, "local-user")
    }

    func testLocalAcceptUpsertsAcceptedShare() async throws {
        let share = makeShare(id: "local-fixture", shareCode: "fixture-code")
        let store = SharedQuestionListStore(localOwnedShares: [share])

        let preview = try await store.previewShare(shareCode: "fixture-code")
        XCTAssertEqual(preview.shareId, "local-fixture")
        XCTAssertFalse(preview.isAccepted)

        let acceptedShareId = try await store.acceptShare(
            shareCode: "fixture-code",
            currentUserId: "recipient-user"
        )

        XCTAssertEqual(acceptedShareId, "local-fixture")
        XCTAssertNotNil(store.acceptedShare(withID: acceptedShareId))
        XCTAssertEqual(store.acceptedShare(withID: acceptedShareId)?.recipient.recipientId, "recipient-user")
    }

    func testLocalDisableLinkUpdatesOwnedShare() async throws {
        let share = makeShare(id: "share", shareCode: "share-code")
        let store = SharedQuestionListStore(localOwnedShares: [share])

        try await store.disableLink(for: share)

        XCTAssertEqual(store.ownedShare(withID: share.id)?.isLinkEnabled, false)
        XCTAssertEqual(store.ownedShare(withID: share.id)?.shareCode, "share-code")
        XCTAssertEqual(store.ownedShare(withID: share.id)?.status, .active)
    }

    func testLocalRegenerateLinkUpdatesOwnedShareAndReenablesLink() async throws {
        let share = makeShare(id: "share", shareCode: "old-code", isLinkEnabled: false)
        let store = SharedQuestionListStore(localOwnedShares: [share])

        let result = try await store.regenerateLink(for: share)

        XCTAssertEqual(result.shareId, share.id)
        XCTAssertNotEqual(result.shareCode, "old-code")
        XCTAssertEqual(store.ownedShare(withID: share.id)?.shareCode, result.shareCode)
        XCTAssertEqual(store.ownedShare(withID: share.id)?.isLinkEnabled, true)
        XCTAssertEqual(
            result.shareURL.absoluteString,
            "https://ttbp-9d652.web.app/share/lists/\(result.shareCode)"
        )
    }

    func testLocalRevokeUpdatesOwnedShareStatus() async throws {
        let share = makeShare(id: "share")
        let store = SharedQuestionListStore(localOwnedShares: [share])

        try await store.revoke(share)

        XCTAssertEqual(store.ownedShare(withID: share.id)?.status, .revoked)
    }

    func testOwnerAnswerSnapshotStaysUnchangedAfterLiveAnswerEditAndShareUpdate() async throws {
        let originalSnapshot = QuestionListShare.normalizedAnswers(["Original", "Snapshot", ""])
        let share = makeShare(id: "share", ownerAnswerSnapshots: ["q1": originalSnapshot])
        let store = SharedQuestionListStore(localOwnedShares: [share])
        let questionModel = QuestionModel(localQuestions: [])

        // Simulates the owner editing their live answer for the same question after the
        // share (and its snapshot) already exists.
        questionModel.cache(
            NormalizedAnswer(texts: ["Edited", "Live", "Answer"], urls: [nil, nil, nil], attributions: [nil, nil, nil]),
            for: "q1"
        )

        // Exercises the one place a client-held share is copy-constructed after creation
        // (`QuestionListShare.updated`) so a future edit that starts threading live
        // answers through it would fail this assertion.
        try await store.disableLink(for: share)

        XCTAssertEqual(questionModel.myAnswers(for: "q1"), ["Edited", "Live", "Answer"])
        XCTAssertEqual(store.ownedShare(withID: share.id)?.isLinkEnabled, false)
        XCTAssertEqual(store.ownedShare(withID: share.id)?.ownerAnswerSnapshots["q1"], originalSnapshot)
    }

    private func makeShare(
        id: String,
        shareCode: String? = nil,
        status: QuestionListShareStatus = .active,
        isLinkEnabled: Bool = true,
        updatedAt: Date = Date(),
        ownerAnswerSnapshots: [String: [String]] = [:]
    ) -> QuestionListShare {
        QuestionListShare(
            id: id,
            ownerId: "owner",
            ownerDisplayName: "Owner",
            sourceListId: "list-1",
            listName: "List \(id)",
            questionIds: ["q1"],
            includeOwnerAnswers: false,
            ownerAnswerSnapshots: ownerAnswerSnapshots,
            shareCode: shareCode ?? "code-\(id)",
            recipientCap: QuestionListShare.defaultRecipientCap,
            acceptedRecipientCount: 0,
            status: status,
            isLinkEnabled: isLinkEnabled,
            createdAt: updatedAt,
            updatedAt: updatedAt
        )
    }

    private func makeList(
        id: String,
        questionIds: [String],
        updatedAt: Date = Date()
    ) -> QuestionList {
        QuestionList(
            id: id,
            ownerId: "owner",
            name: "List \(id)",
            questionIds: questionIds,
            visibility: "private",
            createdAt: updatedAt,
            updatedAt: updatedAt
        )
    }

    private func makeRecipient(
        shareId: String,
        updatedAt: Date
    ) -> QuestionListShareRecipient {
        QuestionListShareRecipient(
            id: "recipient-\(shareId)",
            shareId: shareId,
            recipientId: "recipient-\(shareId)",
            recipientDisplayName: "Recipient",
            status: .accepted,
            latestReplyAnswerSnapshots: [:],
            repliedAt: nil,
            unreadByOwner: false,
            acceptedAt: updatedAt,
            updatedAt: updatedAt
        )
    }
}

/// Minimal `QuestionListShareServicing` conformance shaped like the live actor: no fixture
/// listener publish, `createShare` returns a canned result. Exists so
/// `testLiveCreateShareDoesNotInsertPlaceholderOwnerName` can exercise `SharedQuestionListStore`'s
/// non-fixture initializer path without a real Firebase backend.
@MainActor
private final class FakeLiveQuestionListShareService: QuestionListShareServicing {
    func ownedSharesListener(
        userId: String,
        completion: @escaping (Result<[QuestionListShare], Error>) -> Void
    ) async -> QuestionListShareListenerHandle {
        FakeQuestionListShareListenerHandle()
    }

    func acceptedRecipientsListener(
        userId: String,
        completion: @escaping (Result<[QuestionListShareRecipient], Error>) -> Void
    ) async -> QuestionListShareListenerHandle {
        FakeQuestionListShareListenerHandle()
    }

    func fetchShare(shareId: String) async throws -> QuestionListShare {
        throw QuestionListShareService.ShareError.invalidResponse
    }

    func fetchRecipients(shareId: String) async throws -> [QuestionListShareRecipient] { [] }

    func fetchAcceptedShare(shareId: String, recipientId: String) async throws -> AcceptedQuestionListShare {
        throw QuestionListShareService.ShareError.invalidResponse
    }

    func createShare(listId: String, includeOwnerAnswers: Bool) async throws -> QuestionListShareCreationResult {
        QuestionListShareCreationResult(
            shareId: "live-share-1",
            shareCode: "live-code-1",
            shareURL: URL(string: "https://ttbp-9d652.web.app/share/lists/live-code-1")!
        )
    }

    func previewShare(shareCode: String) async throws -> QuestionListSharePreview {
        throw QuestionListShareService.ShareError.invalidResponse
    }

    func acceptShare(shareCode: String, actingAs currentUserId: String) async throws -> String {
        throw QuestionListShareService.ShareError.invalidResponse
    }

    func disableShare(shareId: String) async throws {}

    func regenerateLink(shareId: String) async throws -> QuestionListShareCreationResult {
        throw QuestionListShareService.ShareError.invalidResponse
    }

    func revokeShare(shareId: String) async throws {}
    func leaveShare(shareId: String) async throws {}
    func sendReply(shareId: String) async throws {}
    func markReplySeen(shareId: String, recipientId: String) async throws {}
}

private struct FakeQuestionListShareListenerHandle: QuestionListShareListenerHandle {
    func remove() {}
}
