import XCTest
@testable import TTB

/// The write-then-patch choreography behind every admin action, asserted through one interface.
///
/// None of this was reachable before AD-4. The eight admin members sat on `QuestionModel` and each
/// one called Firestore directly, so the only way to exercise the local patch was the
/// `questionService == nil` local-mode branch — which skipped the backend call entirely and therefore
/// never tested the ordering that matters: the backend write happens first, and the local corpus is
/// patched only if it succeeded.
///
/// The other thing these tests pin is separation. The store holds its own corpus. `QuestionModel`'s
/// read model is built from two query-filtered listeners, and the bug this split fixes was
/// `refreshAdminQuestions` overwriting that read model with this unfiltered one.
@MainActor
final class QuestionModerationStoreTests: XCTestCase {

    // MARK: - The corpus

    func testRefreshPublishesTheWholeUnfilteredCorpus() async throws {
        let service = FakeQuestionModerationService(questions: [
            question("q1", status: .pending),
            question("q2", status: .approved),
            question("q3", status: .rejected),
        ])
        let store = makeStore(service: service)

        try await store.refresh()

        XCTAssertEqual(store.questions.map(\.id), ["q1", "q2", "q3"])
    }

    /// `refreshAdminQuestions` swallowed its failure into `QuestionModel.error`, which the admin screen
    /// does not read — `CategoryQuestionsView` does. So an admin refresh failure alerted on a user
    /// screen and left the admin list silently stale. Throwing puts the failure where the caller is.
    func testRefreshThrowsRatherThanSwallowingTheFailure() async {
        let service = FakeQuestionModerationService(questions: [])
        service.failNextWrite = true
        let store = makeStore(service: service)

        do {
            try await store.refresh()
            XCTFail("Expected refresh to throw")
        } catch {
            XCTAssertTrue(store.questions.isEmpty)
        }
    }

    // MARK: - Approve and reject

    func testApprovingWritesToTheBackendThenPatchesTheCorpus() async throws {
        let service = FakeQuestionModerationService(questions: [question("q1", status: .pending)])
        let store = makeStore(service: service)
        try await store.refresh()

        try await store.approve(store.questions[0])

        XCTAssertEqual(service.moderationCalls.count, 1)
        XCTAssertEqual(service.moderationCalls[0].questionId, "q1")
        XCTAssertEqual(service.moderationCalls[0].status, .approved)
        XCTAssertNil(service.moderationCalls[0].rejectionReason)
        XCTAssertEqual(service.moderationCalls[0].moderatedBy, "admin-1")
        XCTAssertEqual(store.questions[0].moderationStatus, .approved)
    }

    func testRejectingCarriesTheReasonToTheBackendAndTheCorpus() async throws {
        let service = FakeQuestionModerationService(questions: [question("q1", status: .pending)])
        let store = makeStore(service: service)
        try await store.refresh()

        try await store.reject(store.questions[0], reason: "  off topic  ")

        XCTAssertEqual(service.moderationCalls[0].status, .rejected)
        XCTAssertEqual(service.moderationCalls[0].rejectionReason, "  off topic  ")
        XCTAssertEqual(store.questions[0].moderationStatus, .rejected)
        XCTAssertEqual(store.questions[0].rejectionReason, "off topic")
    }

    /// The ordering the local-mode branch could never test. A failed write must leave the corpus
    /// alone, or the admin sees a decision the backend rejected.
    func testAFailedModerationWriteLeavesTheCorpusUntouched() async throws {
        let service = FakeQuestionModerationService(questions: [question("q1", status: .pending)])
        let store = makeStore(service: service)
        try await store.refresh()
        service.failNextWrite = true

        do {
            try await store.approve(store.questions[0])
            XCTFail("Expected approve to throw")
        } catch {
            XCTAssertEqual(store.questions[0].moderationStatus, .pending)
        }
    }

    func testTheModerationTimestampComesFromTheInjectedClock() async throws {
        let service = FakeQuestionModerationService(questions: [question("q1", status: .pending)])
        let stamped = Date(timeIntervalSince1970: 1_700_000_000)
        let store = makeStore(service: service, now: { stamped })
        try await store.refresh()

        try await store.approve(store.questions[0])

        XCTAssertEqual(store.questions[0].moderatedAt, stamped)
    }

    // MARK: - Featured placement

    func testSettingAPlacementPatchesOnlyThatQuestion() async throws {
        let service = FakeQuestionModerationService(questions: [
            question("q1", status: .approved),
            question("q2", status: .approved),
        ])
        let store = makeStore(service: service)
        try await store.refresh()

        try await store.setFeaturedPlacement(.home, for: store.questions[0])

        XCTAssertEqual(service.placementCalls.map(\.questionId), ["q1"])
        XCTAssertEqual(store.questions[0].featuredPlacement, .home)
        XCTAssertEqual(store.questions[1].featuredPlacement, .none)
    }

    // MARK: - Edit

    func testEditingWritesTheWholeQuestionAndPatchesTheCorpus() async throws {
        let service = FakeQuestionModerationService(questions: [question("q1", status: .approved)])
        let store = makeStore(service: service)
        try await store.refresh()

        try await store.edit(
            store.questions[0],
            newText: "Edited?",
            newCategory: "Personal",
            languageCode: "en"
        )

        XCTAssertEqual(service.updateCalls.map(\.id), ["q1"])
        XCTAssertEqual(service.updateCalls[0].category, "Personal")
        XCTAssertEqual(store.questions[0].category, "Personal")
        XCTAssertEqual(store.questions[0].localizedTexts["en"], "Edited?")
    }

    // MARK: - Add and delete

    func testAddingAppendsToTheCorpusAfterTheBackendAccepts() async throws {
        let service = FakeQuestionModerationService(questions: [question("q1", status: .approved)])
        let store = makeStore(service: service)
        try await store.refresh()

        try await store.add(question("q2", status: .pending))

        XCTAssertEqual(service.addCalls.map(\.id), ["q2"])
        XCTAssertEqual(store.questions.map(\.id), ["q1", "q2"])
    }

    func testAFailedAddLeavesTheCorpusUntouched() async throws {
        let service = FakeQuestionModerationService(questions: [question("q1", status: .approved)])
        let store = makeStore(service: service)
        try await store.refresh()
        service.failNextWrite = true

        do {
            try await store.add(question("q2", status: .pending))
            XCTFail("Expected add to throw")
        } catch {
            XCTAssertEqual(store.questions.map(\.id), ["q1"])
        }
    }

    func testDeletingRemovesFromTheCorpusAfterTheBackendAccepts() async throws {
        let service = FakeQuestionModerationService(questions: [
            question("q1", status: .approved),
            question("q2", status: .pending),
        ])
        let store = makeStore(service: service)
        try await store.refresh()

        try await store.delete(store.questions[0])

        XCTAssertEqual(service.deleteCalls, ["q1"])
        XCTAssertEqual(store.questions.map(\.id), ["q2"])
    }

    func testAFailedDeleteLeavesTheCorpusUntouched() async throws {
        let service = FakeQuestionModerationService(questions: [question("q1", status: .approved)])
        let store = makeStore(service: service)
        try await store.refresh()
        service.failNextWrite = true

        do {
            try await store.delete(store.questions[0])
            XCTFail("Expected delete to throw")
        } catch {
            XCTAssertEqual(store.questions.map(\.id), ["q1"])
        }
    }

    /// A question the corpus has never seen is appended rather than dropped. The admin screen can hold
    /// a `Question` value that predates the last refresh, and losing the patch would make the action
    /// look like it did nothing.
    func testPatchingAQuestionTheCorpusDoesNotHoldAppendsIt() async throws {
        let service = FakeQuestionModerationService(questions: [])
        let store = makeStore(service: service)
        try await store.refresh()

        try await store.approve(question("q9", status: .pending))

        XCTAssertEqual(store.questions.map(\.id), ["q9"])
        XCTAssertEqual(store.questions[0].moderationStatus, .approved)
    }

    // MARK: - Helpers

    private func makeStore(
        service: QuestionModerating,
        moderatorID: String? = "admin-1",
        now: @escaping () -> Date = { Date(timeIntervalSince1970: 1_700_000_000) }
    ) -> QuestionModerationStore {
        QuestionModerationStore(
            service: service,
            currentModeratorID: { moderatorID },
            now: now
        )
    }

    private func question(_ id: String, status: QuestionModerationStatus) -> Question {
        Question(
            id: id,
            text: "Question \(id)?",
            category: "Daily",
            localizedTexts: ["en": "Question \(id)?"],
            languageCode: "en",
            source: .userCreated,
            createdAt: Date(timeIntervalSince1970: 1_600_000_000),
            moderationStatus: status,
            featuredPlacement: .none
        )
    }
}

// MARK: - Fake

/// In-memory adapter. It records calls and can be told to fail the next write, which is what makes the
/// backend-first ordering assertable. `@MainActor` like the suite, so the tests read its recorded calls
/// without an `await` and `QuestionModerating`'s `Sendable` requirement holds.
@MainActor
private final class FakeQuestionModerationService: QuestionModerating {
    struct ModerationCall {
        let questionId: String
        let status: QuestionModerationStatus
        let rejectionReason: String?
        let moderatedBy: String?
    }

    struct PlacementCall {
        let questionId: String
        let placement: QuestionFeaturedPlacement
    }

    private let questions: [Question]
    var failNextWrite = false

    private(set) var moderationCalls: [ModerationCall] = []
    private(set) var placementCalls: [PlacementCall] = []
    private(set) var updateCalls: [Question] = []
    private(set) var addCalls: [Question] = []
    private(set) var deleteCalls: [String] = []

    init(questions: [Question]) {
        self.questions = questions
    }

    private func failIfAsked() throws {
        guard failNextWrite else { return }
        failNextWrite = false
        throw NSError(domain: "FakeQuestionModerationService", code: 1)
    }

    func allQuestions() async throws -> [Question] {
        try failIfAsked()
        return questions
    }

    func add(_ question: Question) async throws {
        try failIfAsked()
        addCalls.append(question)
    }

    func update(_ question: Question) async throws {
        try failIfAsked()
        updateCalls.append(question)
    }

    func delete(id questionId: String) async throws {
        try failIfAsked()
        deleteCalls.append(questionId)
    }

    func updateModeration(
        questionId: String,
        status: QuestionModerationStatus,
        rejectionReason: String?,
        moderatedBy: String?
    ) async throws {
        try failIfAsked()
        moderationCalls.append(
            ModerationCall(
                questionId: questionId,
                status: status,
                rejectionReason: rejectionReason,
                moderatedBy: moderatedBy
            )
        )
    }

    func updateFeaturedPlacement(
        questionId: String,
        placement: QuestionFeaturedPlacement
    ) async throws {
        try failIfAsked()
        placementCalls.append(PlacementCall(questionId: questionId, placement: placement))
    }
}
