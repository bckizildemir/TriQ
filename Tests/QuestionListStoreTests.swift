import XCTest
@testable import TTB

@MainActor
final class QuestionListStoreTests: XCTestCase {
    func testApplyListenerSnapshotSortsByUpdatedAt() {
        let older = makeList(id: "older", updatedAt: Date(timeIntervalSince1970: 10))
        let newer = makeList(id: "newer", updatedAt: Date(timeIntervalSince1970: 20))
        let model = QuestionListStore(localLists: [])

        model.applyListenerSnapshotForTesting([older, newer])

        XCTAssertEqual(model.lists.map(\.id), ["newer", "older"])
    }

    func testCreateRenameDeleteListInLocalMode() async throws {
        let model = QuestionListStore(localLists: [])

        let created = try await model.createList(named: " Family ")
        XCTAssertEqual(created.name, "Family")
        XCTAssertEqual(model.lists.count, 1)

        try await model.updateList(created, name: "Beloved")
        XCTAssertEqual(model.lists.first?.name, "Beloved")

        guard let updated = model.lists.first else {
            XCTFail("Expected updated list")
            return
        }
        try await model.deleteList(updated)
        XCTAssertTrue(model.lists.isEmpty)
    }

    func testSetQuestionInListAddsAndRemovesMembership() async throws {
        let list = makeList(id: "list-1")
        let model = QuestionListStore(localLists: [list])

        try await model.setQuestion("q1", in: list, isIncluded: true)
        XCTAssertEqual(model.lists.first?.questionIds, ["q1"])
        XCTAssertTrue(model.isQuestion("q1", in: "list-1"))
        XCTAssertEqual(model.listsContaining(questionId: "q1").map(\.id), ["list-1"])

        guard let updated = model.lists.first else {
            XCTFail("Expected updated list")
            return
        }
        try await model.setQuestion("q1", in: updated, isIncluded: false)
        XCTAssertEqual(model.lists.first?.questionIds, [])
    }

    func testQuestionsInListPreservesOrderAndIgnoresMissingQuestions() {
        let list = makeList(id: "list-1", questionIds: ["q2", "missing", "q1"])
        let questionOne = Question(id: "q1", text: "One?", category: "Daily")
        let questionTwo = Question(id: "q2", text: "Two?", category: "Daily")
        let listModel = QuestionListStore(localLists: [list])
        let questionModel = QuestionModel(localQuestions: [questionOne, questionTwo])

        let questions = listModel.questions(in: list, using: questionModel)

        XCTAssertEqual(questions.map(\.id), ["q2", "q1"])
    }

    func testFailedConcurrentRenameDoesNotEraseSuccessfulRenameOfAnotherList() async throws {
        let firstList = makeList(id: "list-a")
        let secondList = makeList(id: "list-b")
        let service = MockQuestionListService()
        await service.blockUpdate(for: firstList.id, failsWhenResumed: true)
        let model = QuestionListStore(
            questionListService: service,
            userId: "user-1",
            observesAuth: false,
            startsListener: false
        )
        model.applyListenerSnapshotForTesting([firstList, secondList])

        let failedRename = Task {
            try await model.updateList(firstList, name: "Failed rename")
        }
        await service.waitUntilUpdateStarts(for: firstList.id)

        try await model.updateList(secondList, name: "Successful rename")
        await service.resumeUpdate(for: firstList.id)

        do {
            try await failedRename.value
            XCTFail("Expected the first rename to fail")
        } catch MockQuestionListService.MockError.updateFailed {
            // Expected.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertEqual(
            model.lists.first(where: { $0.id == firstList.id })?.name,
            firstList.name
        )
        XCTAssertEqual(
            model.lists.first(where: { $0.id == secondList.id })?.name,
            "Successful rename"
        )
        XCTAssertNil(model.error)
    }

    func testSameListMembershipMutationsExecuteAddBeforeRemove() async throws {
        let list = makeList(id: "list-a")
        let service = MockQuestionListService()
        await service.blockSetQuestion(for: list.id)
        let model = QuestionListStore(
            questionListService: service,
            userId: "user-1",
            observesAuth: false,
            startsListener: false
        )
        model.applyListenerSnapshotForTesting([list])

        let addition = Task {
            try await model.setQuestion("question-1", in: list, isIncluded: true)
        }
        await service.waitUntilSetQuestionCallCount(1, for: list.id)

        let removal = Task {
            try await model.setQuestion("question-1", in: list, isIncluded: false)
        }
        await model.waitUntilRemoteMutationIsQueuedForTesting(for: list.id)

        let callsBeforeAdditionCompletes =
            await service.setQuestionInclusionValues(for: list.id)
        XCTAssertEqual(callsBeforeAdditionCompletes, [true])
        XCTAssertTrue(model.isQuestion("question-1", in: list.id))

        await service.resumeSetQuestion(for: list.id)
        await service.waitUntilSetQuestionCallCount(2, for: list.id)
        try await addition.value
        try await removal.value

        let completedCalls = await service.setQuestionInclusionValues(for: list.id)
        XCTAssertEqual(completedCalls, [true, false])
        XCTAssertFalse(model.isQuestion("question-1", in: list.id))
    }

    func testTwoFailedQueuedRenamesRestoreConfirmedState() async {
        let list = makeList(id: "list-a")
        let service = MockQuestionListService()
        await service.blockUpdate(for: list.id, failsWhenResumed: true)
        let model = QuestionListStore(
            questionListService: service,
            userId: "user-1",
            observesAuth: false,
            startsListener: false
        )
        model.applyListenerSnapshotForTesting([list])

        let firstRename = Task {
            try await model.updateList(list, name: "First optimistic name")
        }
        await service.waitUntilUpdateStarts(for: list.id)

        let secondRename = Task {
            try await model.updateList(list, name: "Second optimistic name")
        }
        await model.waitUntilRemoteMutationIsQueuedForTesting(for: list.id)
        XCTAssertEqual(
            model.lists.first(where: { $0.id == list.id })?.name,
            "First optimistic name"
        )

        await service.resumeUpdate(for: list.id)
        await assertMockUpdateFailed(firstRename)
        await assertMockUpdateFailed(secondRename)

        XCTAssertEqual(
            model.lists.first(where: { $0.id == list.id })?.name,
            list.name
        )
    }

    func testFailedMutationCannotRollbackNewerAuthoritativeSnapshot() async {
        let list = makeList(id: "list-a")
        var authoritativeList = list
        authoritativeList.name = "Server-confirmed name"
        authoritativeList.updatedAt = Date(timeIntervalSince1970: 100)
        let service = MockQuestionListService()
        await service.blockUpdate(for: list.id, failsWhenResumed: true)
        let model = QuestionListStore(
            questionListService: service,
            userId: "user-1",
            observesAuth: false,
            startsListener: false
        )
        model.applyListenerSnapshotForTesting([list])

        let failedRename = Task {
            try await model.updateList(list, name: "Optimistic name")
        }
        await service.waitUntilUpdateStarts(for: list.id)
        model.applyListenerSnapshotForTesting([authoritativeList])
        await service.resumeUpdate(for: list.id)

        do {
            try await failedRename.value
            XCTFail("Expected the rename to fail")
        } catch MockQuestionListService.MockError.updateFailed {
            // Expected.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertEqual(
            model.lists.first(where: { $0.id == list.id })?.name,
            "Server-confirmed name"
        )
    }

    func testLateSnapshotFromPreviousUserCannotContaminateCurrentSession() async {
        let service = MockQuestionListService()
        let model = QuestionListStore(
            questionListService: service,
            userId: "user-a",
            observesAuth: false
        )
        await service.waitUntilListenerStarts(for: "user-a")

        model.transitionToUser(withID: "user-b")
        await service.waitUntilListenerStarts(for: "user-b")

        await service.sendSnapshot(
            [makeList(id: "stale", ownerId: "user-a")],
            for: "user-a"
        )
        await service.sendSnapshot(
            [makeList(id: "current", ownerId: "user-b")],
            for: "user-b"
        )
        await waitForListIDs(["current"], on: model)
        XCTAssertEqual(model.lists.map(\.id), ["current"])
    }

    func testFailedMutationFromPreviousUserCannotRestoreTheirList() async {
        let list = makeList(id: "user-a-list", ownerId: "user-a")
        let service = MockQuestionListService()
        await service.blockUpdate(for: list.id, failsWhenResumed: true)
        let model = QuestionListStore(
            questionListService: service,
            userId: "user-a",
            observesAuth: false,
            startsListener: false
        )
        model.applyListenerSnapshotForTesting([list])

        let rename = Task {
            try await model.updateList(list, name: "Stale rename")
        }
        await service.waitUntilUpdateStarts(for: list.id)
        model.transitionToUser(withID: "user-b")
        await service.resumeUpdate(for: list.id)

        do {
            try await rename.value
            XCTFail("Expected the previous user's rename to fail")
        } catch MockQuestionListService.MockError.updateFailed {
            // Expected.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertTrue(model.lists.isEmpty)
        XCTAssertNil(model.error)
    }

    func testQueuedMutationFromPreviousUserDoesNotExecuteAfterTransition() async {
        let list = makeList(id: "user-a-list", ownerId: "user-a")
        let service = MockQuestionListService()
        await service.blockSetQuestion(for: list.id)
        let model = QuestionListStore(
            questionListService: service,
            userId: "user-a",
            observesAuth: false,
            startsListener: false
        )
        model.applyListenerSnapshotForTesting([list])

        let addition = Task {
            try await model.setQuestion("question-1", in: list, isIncluded: true)
        }
        await service.waitUntilSetQuestionCallCount(1, for: list.id)

        let removal = Task {
            try await model.setQuestion("question-1", in: list, isIncluded: false)
        }
        await model.waitUntilRemoteMutationIsQueuedForTesting(for: list.id)

        model.transitionToUser(withID: "user-b")
        await service.resumeSetQuestion(for: list.id)

        await assertSessionChanged(addition)
        await assertSessionChanged(removal)
        let remoteCalls = await service.setQuestionInclusionValues(for: list.id)
        XCTAssertEqual(remoteCalls, [true])
        XCTAssertTrue(model.lists.isEmpty)
        XCTAssertNil(model.error)
    }

    func testMissingListMutationCannotSuppressRollbackOfFailedDelete() async {
        let list = makeList(id: "list-a")
        let service = MockQuestionListService()
        await service.blockDelete(for: list.id, failsWhenResumed: true)
        let model = QuestionListStore(
            questionListService: service,
            userId: "user-1",
            observesAuth: false,
            startsListener: false
        )
        model.applyListenerSnapshotForTesting([list])

        let deletion = Task {
            try await model.deleteList(list)
        }
        await service.waitUntilDeleteStarts(for: list.id)

        do {
            try await model.updateList(list, name: "Impossible rename")
            XCTFail("Expected a locally missing list to be rejected")
        } catch QuestionListStoreError.localListNotFound(let listID) {
            XCTAssertEqual(listID, list.id)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        await service.resumeDelete(for: list.id)
        do {
            try await deletion.value
            XCTFail("Expected deletion to fail")
        } catch MockQuestionListService.MockError.deleteFailed {
            // Expected.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertEqual(model.lists.map(\.id), [list.id])
    }

    func testCreateFinishingAfterUserTransitionCannotContaminateNewSession() async {
        let service = MockQuestionListService()
        await service.blockCreate(for: "user-a", returning: "created-for-a")
        let model = QuestionListStore(
            questionListService: service,
            userId: "user-a",
            observesAuth: false,
            startsListener: false
        )

        let creation = Task {
            try await model.createList(named: "User A list")
        }
        await service.waitUntilCreateStarts(for: "user-a")
        model.transitionToUser(withID: "user-b")
        await service.resumeCreate(for: "user-a")

        do {
            _ = try await creation.value
            XCTFail("Expected stale list creation to be rejected")
        } catch QuestionListStoreError.sessionChanged {
            // Expected.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertTrue(model.lists.isEmpty)
        XCTAssertNil(model.error)
    }

    private func makeList(
        id: String,
        ownerId: String = "user-1",
        questionIds: [String] = [],
        updatedAt: Date = Date()
    ) -> QuestionList {
        QuestionList(
            id: id,
            ownerId: ownerId,
            name: "List \(id)",
            questionIds: questionIds,
            visibility: "private",
            createdAt: updatedAt,
            updatedAt: updatedAt
        )
    }

    private func waitForListIDs(
        _ expectedIDs: [String],
        on model: QuestionListStore
    ) async {
        for _ in 0..<100 {
            if model.lists.map(\.id) == expectedIDs {
                return
            }
            await Task.yield()
        }

        XCTFail("Timed out waiting for list IDs \(expectedIDs)")
    }

    private func assertSessionChanged(
        _ task: Task<Void, Error>,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            try await task.value
            XCTFail("Expected the account transition to invalidate the mutation", file: file, line: line)
        } catch QuestionListStoreError.sessionChanged {
            // Expected.
        } catch {
            XCTFail("Unexpected error: \(error)", file: file, line: line)
        }
    }

    private func assertMockUpdateFailed(
        _ task: Task<Void, Error>,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            try await task.value
            XCTFail("Expected the update to fail", file: file, line: line)
        } catch MockQuestionListService.MockError.updateFailed {
            // Expected.
        } catch {
            XCTFail("Unexpected error: \(error)", file: file, line: line)
        }
    }
}
