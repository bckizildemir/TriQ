import Foundation
import Testing
@testable import TTB

@MainActor
struct QuestionListBackgroundCreateTests {
    private let service = MockQuestionListService()
    private let store: QuestionListStore
    private let failures = FailureLog()

    init() {
        store = QuestionListStore(
            questionListService: service,
            userId: "user-1",
            observesAuth: false,
            startsListener: false
        )
        let log = failures
        store.creationFailureHandler = { log.record($0) }
    }

    @Test func pendingRowShowsUntilTheServerConfirms() async throws {
        await service.blockCreate(for: "user-1", returning: "new-list")

        let task = store.startCreate(named: " Family ")
        await service.waitUntilCreateStarts(for: "user-1")

        #expect(store.pendingCreations.map(\.name) == ["Family"])
        #expect(store.pendingCreations.first?.state == .saving)
        #expect(store.lists.isEmpty)

        await service.resumeCreate(for: "user-1")
        await task.value

        #expect(store.pendingCreations.isEmpty)
        #expect(store.lists.map(\.id) == ["new-list"])
        #expect(failures.values.isEmpty)
    }

    @Test func snapshotBeforeTheCreateReturnsNeitherDropsNorDuplicatesTheList() async {
        await service.blockCreate(for: "user-1", returning: "new-list")
        let task = store.startCreate(named: "Family")
        await service.waitUntilCreateStarts(for: "user-1")

        store.applyListenerSnapshotForTesting([makeList(id: "new-list")])
        #expect(store.pendingCreations.count == 1)

        await service.resumeCreate(for: "user-1")
        await task.value

        #expect(store.lists.map(\.id) == ["new-list"])
        #expect(store.pendingCreations.isEmpty)
    }

    @Test func snapshotAfterTheCreateReturnsKeepsTheListOnce() async {
        await service.blockCreate(for: "user-1", returning: "new-list")
        let task = store.startCreate(named: "Family")
        await service.waitUntilCreateStarts(for: "user-1")
        await service.resumeCreate(for: "user-1")
        await task.value

        store.applyListenerSnapshotForTesting([makeList(id: "new-list")])

        #expect(store.lists.map(\.id) == ["new-list"])
    }

    @Test func failedCreateLeavesNotSavedRowAndToastWithoutAlert() async {
        await service.failNextCreate(for: "user-1")

        await store.startCreate(named: "Family").value

        #expect(store.pendingCreations.first?.state == .failed)
        #expect(store.lists.isEmpty)
        #expect(failures.values == [.createFailed])
        #expect(store.error == nil)
    }

    @Test func retryRunsTheCreateAgainWithTheSameName() async throws {
        await service.failNextCreate(for: "user-1")
        await store.startCreate(named: "Family").value
        let pendingID = try #require(store.pendingCreations.first?.id)

        let retry = try #require(store.retryCreate(pendingID))
        #expect(store.pendingCreations.first?.state == .saving)
        await retry.value

        #expect(store.pendingCreations.isEmpty)
        #expect(store.lists.map(\.name) == ["Family"])
        #expect(await service.createdNames == ["Family", "Family"])
    }

    @Test func deleteRemovesAFailedRow() async throws {
        await service.failNextCreate(for: "user-1")
        await store.startCreate(named: "Family").value
        let pendingID = try #require(store.pendingCreations.first?.id)

        store.discardCreate(pendingID)

        #expect(store.pendingCreations.isEmpty)
        #expect(store.retryCreate(pendingID) == nil)
    }

    @Test func aSavingRowCannotBeDiscardedOrRetried() async throws {
        await service.blockCreate(for: "user-1", returning: "new-list")
        let task = store.startCreate(named: "Family")
        await service.waitUntilCreateStarts(for: "user-1")
        let pendingID = try #require(store.pendingCreations.first?.id)

        store.discardCreate(pendingID)
        #expect(store.retryCreate(pendingID) == nil)
        #expect(store.pendingCreations.count == 1)

        await service.resumeCreate(for: "user-1")
        await task.value
        #expect(await service.createdNames == ["Family"])
    }

    @Test func createAndAddAddsTheQuestionToTheNewList() async {
        await service.blockCreate(for: "user-1", returning: "new-list")
        let task = store.startCreate(named: "Family", addingQuestionID: "q1")
        await service.waitUntilCreateStarts(for: "user-1")
        await service.resumeCreate(for: "user-1")
        await task.value

        #expect(store.lists.first?.questionIds == ["q1"])
        #expect(store.pendingCreations.isEmpty)
        #expect(failures.values.isEmpty)
    }

    @Test func failedAddKeepsTheListAndNeverCreatesASecondOne() async {
        await service.failSetQuestion(for: "new-list")
        await service.blockCreate(for: "user-1", returning: "new-list")
        let task = store.startCreate(named: "Family", addingQuestionID: "q1")
        await service.waitUntilCreateStarts(for: "user-1")
        await service.resumeCreate(for: "user-1")
        await task.value

        #expect(store.lists.map(\.id) == ["new-list"])
        #expect(store.pendingCreations.isEmpty)
        #expect(failures.values == [.addQuestionFailed])
        #expect(store.error == nil)
        #expect(await service.createdNames == ["Family"])
    }

    @Test func sessionChangeDuringACreateLeavesNoRowNoToastAndNoList() async {
        await service.blockCreate(for: "user-1", returning: "new-list")
        let task = store.startCreate(named: "Family")
        await service.waitUntilCreateStarts(for: "user-1")

        store.transitionToUser(withID: "user-2")
        #expect(store.pendingCreations.isEmpty)

        await service.resumeCreate(for: "user-1")
        await task.value

        #expect(store.pendingCreations.isEmpty)
        #expect(store.lists.isEmpty)
        #expect(failures.values.isEmpty)
    }

    private func makeList(id: String) -> QuestionList {
        QuestionList(
            id: id,
            ownerId: "user-1",
            name: "Family",
            questionIds: [],
            visibility: "private",
            createdAt: Date(),
            updatedAt: Date()
        )
    }
}

/// Collects what the store's failure handler reports.
@MainActor
private final class FailureLog {
    private(set) var values: [QuestionListCreationFailure] = []

    func record(_ failure: QuestionListCreationFailure) {
        values.append(failure)
    }
}
