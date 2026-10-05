import UIKit
import XCTest
@testable import TTB

/// Exercises the save choreography that used to live in `QuestionCardExpandedView`.
///
/// Every test here was impossible before AD-2. The orchestration sat in a `View`, and the only reachable
/// persistence branch was the one where `questionService` was nil and saving silently did nothing — so
/// rollback, the compare-and-swap against a stale cache, partial upload failure and orphan cleanup had
/// no coverage at all.
@MainActor
final class AnswerDraftStoreTests: XCTestCase {
    private let questionId = "q-1"

    private func store(
        persister: FakeAnswerPersister = FakeAnswerPersister(),
        images: FakeAnswerImageStore = FakeAnswerImageStore()
    ) -> AnswerDraftStore {
        AnswerDraftStore(persister: persister, images: images)
    }

    // MARK: - What is worth saving
    //
    // These three replace the assertions that `QuestionModel.saveAnswers` carried before it was
    // deleted in commit 1/5. They now hold for one expression instead of a special-cased branch.

    func testEmptyDraftOnUnansweredQuestionPlansNothing() {
        let host = FakeAnswerHost()

        let plan = store().plan(
            for: .fixture(["", "  ", ""]),
            baseline: .empty,
            questionId: questionId,
            in: host
        )

        XCTAssertNil(plan)
        XCTAssertNil(host.stored[questionId])
    }

    func testWhitespaceOnlyEditPlansNothing() {
        let existing = UserAnswer.fixture(questionId: questionId, answers: ["One", "Two", ""])
        let host = FakeAnswerHost(stored: [questionId: existing])
        let baseline = NormalizedAnswer(existing)

        let plan = store().plan(
            for: .fixture([" One ", "Two", ""]),
            baseline: baseline,
            questionId: questionId,
            in: host
        )

        XCTAssertNil(plan)
        XCTAssertEqual(host.stored[questionId]?.answeredAt, existing.answeredAt)
    }

    func testClearingAnsweredQuestionPlansAnEmptySave() {
        let existing = UserAnswer.fixture(questionId: questionId, answers: ["One", "", ""])
        let host = FakeAnswerHost(stored: [questionId: existing])

        let plan = store().plan(
            for: .fixture(["", "", ""]),
            baseline: NormalizedAnswer(existing),
            questionId: questionId,
            in: host
        )

        XCTAssertNotNil(plan)
        XCTAssertEqual(plan?.optimistic.texts, ["", "", ""])
    }

    func testPendingImageWithEmptyTextStillPlansASave() {
        let host = FakeAnswerHost()

        let plan = store().plan(
            for: .fixture(["", "", ""], images: [1: .pendingLocal(UIImage())]),
            baseline: .empty,
            questionId: questionId,
            in: host
        )

        XCTAssertNotNil(plan)
        XCTAssertEqual(plan?.uploads.count, 1)
    }

    func testPlanKeepsSavedURLsAndDropsPendingOnes() {
        let host = FakeAnswerHost()

        let plan = store().plan(
            for: .fixture(
                ["a", "b", "c"],
                images: [
                    0: .saved(url: "https://example.com/kept.jpg", attribution: nil),
                    2: .pendingLocal(UIImage()),
                ]
            ),
            baseline: .empty,
            questionId: questionId,
            in: host
        )

        XCTAssertEqual(plan?.optimistic.urls, ["https://example.com/kept.jpg", nil, nil])
    }

    // MARK: - The save with no images

    func testOptimisticWriteCachesTrimmedTextImmediately() throws {
        let host = FakeAnswerHost()
        let subject = store()
        let plan = try XCTUnwrap(
            subject.plan(for: .fixture([" One ", "Two", ""]), baseline: .empty, questionId: questionId, in: host)
        )

        subject.applyOptimistically(plan, in: host)

        XCTAssertEqual(host.normalized(questionId)?.texts, ["One", "Two", ""])
    }

    func testFinishPersistsTheOptimisticAnswer() async throws {
        let persister = FakeAnswerPersister()
        let host = FakeAnswerHost()
        let subject = store(persister: persister)
        let plan = try XCTUnwrap(
            subject.plan(for: .fixture(["One", "Two", ""]), baseline: .empty, questionId: questionId, in: host)
        )
        subject.applyOptimistically(plan, in: host)

        await subject.finish(plan, in: host)

        let saved = await persister.saved
        XCTAssertEqual(saved.count, 1)
        XCTAssertEqual(saved.first?.texts, ["One", "Two", ""])
        XCTAssertTrue(host.reported.isEmpty)
    }

    func testPersistFailureRollsBackToThePreviousAnswer() async throws {
        let existing = UserAnswer.fixture(questionId: questionId, answers: ["Old", "", ""])
        let host = FakeAnswerHost(stored: [questionId: existing])
        let subject = store(persister: FakeAnswerPersister(failingCalls: [1]))
        let plan = try XCTUnwrap(
            subject.plan(
                for: .fixture(["New", "", ""]),
                baseline: NormalizedAnswer(existing),
                questionId: questionId,
                in: host
            )
        )
        subject.applyOptimistically(plan, in: host)

        await subject.finish(plan, in: host)

        XCTAssertEqual(host.stored[questionId]?.answers, ["Old", "", ""])
        // Restored exactly, not re-stamped: a rollback must not look like a fresh answer.
        XCTAssertEqual(host.stored[questionId]?.answeredAt, existing.answeredAt)
        XCTAssertEqual(host.reported, [.textSaveFailed])
    }

    func testPersistFailureLeavesANewerEditAlone() async throws {
        let existing = UserAnswer.fixture(questionId: questionId, answers: ["Old", "", ""])
        let host = FakeAnswerHost(stored: [questionId: existing])
        let subject = store(persister: FakeAnswerPersister(failingCalls: [1]))
        let plan = try XCTUnwrap(
            subject.plan(
                for: .fixture(["New", "", ""]),
                baseline: NormalizedAnswer(existing),
                questionId: questionId,
                in: host
            )
        )
        subject.applyOptimistically(plan, in: host)

        // The user edits again while the failing save is in flight.
        host.cache(NormalizedAnswer(texts: ["Newer", "", ""], urls: [nil, nil, nil], attributions: [nil, nil, nil]), for: questionId)

        await subject.finish(plan, in: host)

        XCTAssertEqual(host.stored[questionId]?.answers, ["Newer", "", ""])
    }

    func testPersistFailureOnFirstAnswerRemovesTheCacheEntry() async throws {
        let host = FakeAnswerHost()
        let subject = store(persister: FakeAnswerPersister(failingCalls: [1]))
        let plan = try XCTUnwrap(
            subject.plan(for: .fixture(["One", "", ""]), baseline: .empty, questionId: questionId, in: host)
        )
        subject.applyOptimistically(plan, in: host)

        await subject.finish(plan, in: host)

        XCTAssertNil(host.stored[questionId])
        XCTAssertEqual(host.reported, [.textSaveFailed])
    }

    // MARK: - The save with images

    func testUploadsEveryPendingSlotThenPersistsTheReturnedURLs() async throws {
        let persister = FakeAnswerPersister()
        let images = FakeAnswerImageStore(urls: [0: "https://example.com/zero.jpg"])
        let host = FakeAnswerHost()
        let subject = store(persister: persister, images: images)
        let plan = try XCTUnwrap(
            subject.plan(
                for: .fixture(["One", "", ""], images: [0: .pendingLocal(UIImage())]),
                baseline: .empty,
                questionId: questionId,
                in: host
            )
        )
        subject.applyOptimistically(plan, in: host)

        await subject.finish(plan, in: host)

        let saved = await persister.saved
        XCTAssertEqual(saved.count, 2, "text first, then the URLs that arrived")
        XCTAssertEqual(saved.first?.urls, [nil, nil, nil])
        XCTAssertEqual(saved.last?.urls, ["https://example.com/zero.jpg", nil, nil])
        XCTAssertEqual(host.normalized(questionId)?.urls, ["https://example.com/zero.jpg", nil, nil])
        XCTAssertTrue(host.reported.isEmpty)
    }

    func testStaleCacheSkipsTheImageURLWrite() async throws {
        let persister = FakeAnswerPersister()
        let host = FakeAnswerHost()
        let subject = store(persister: persister)
        let plan = try XCTUnwrap(
            subject.plan(
                for: .fixture(["One", "", ""], images: [0: .pendingLocal(UIImage())]),
                baseline: .empty,
                questionId: questionId,
                in: host
            )
        )
        subject.applyOptimistically(plan, in: host)

        // A newer edit takes ownership of the cache while the upload is in flight.
        host.cache(NormalizedAnswer(texts: ["Newer", "", ""], urls: [nil, nil, nil], attributions: [nil, nil, nil]), for: questionId)

        await subject.finish(plan, in: host)

        let saveCount = await persister.saveCount
        XCTAssertEqual(saveCount, 1, "the stale image URLs must not be written")
        XCTAssertEqual(host.stored[questionId]?.answers, ["Newer", "", ""])
    }

    func testPartialUploadFailureKeepsTheSuccessfulSlotAndReportsTheFailedOne() async throws {
        let persister = FakeAnswerPersister()
        let images = FakeAnswerImageStore(urls: [0: "https://example.com/zero.jpg"], failingSlots: [1])
        let host = FakeAnswerHost()
        let subject = store(persister: persister, images: images)
        let plan = try XCTUnwrap(
            subject.plan(
                for: .fixture(
                    ["One", "Two", ""],
                    images: [0: .pendingLocal(UIImage()), 1: .pendingLocal(UIImage())]
                ),
                baseline: .empty,
                questionId: questionId,
                in: host
            )
        )
        subject.applyOptimistically(plan, in: host)

        await subject.finish(plan, in: host)

        let saved = await persister.saved
        XCTAssertEqual(saved.last?.urls, ["https://example.com/zero.jpg", nil, nil])
        XCTAssertEqual(host.reported.count, 1)
        guard case let .imageUploadFailed(slotIndex, _) = host.reported.first else {
            return XCTFail("expected an upload failure for the failing slot, got \(host.reported)")
        }
        XCTAssertEqual(slotIndex, 1)
    }

    func testTextPersistFailureInTheUploadPathAlsoRollsBack() async throws {
        let existing = UserAnswer.fixture(questionId: questionId, answers: ["Old", "", ""])
        let images = FakeAnswerImageStore()
        let host = FakeAnswerHost(stored: [questionId: existing])
        let subject = store(persister: FakeAnswerPersister(failingCalls: [1]), images: images)
        let plan = try XCTUnwrap(
            subject.plan(
                for: .fixture(["New", "", ""], images: [0: .pendingLocal(UIImage())]),
                baseline: NormalizedAnswer(existing),
                questionId: questionId,
                in: host
            )
        )
        subject.applyOptimistically(plan, in: host)

        await subject.finish(plan, in: host)

        // Before AD-2 this path showed an error and left the answer looking saved locally
        // while the backend never received it.
        XCTAssertEqual(host.stored[questionId]?.answers, ["Old", "", ""])
        XCTAssertEqual(host.reported, [.textSaveFailed])
        let uploadedSlots = await images.uploadedSlots
        XCTAssertTrue(uploadedSlots.isEmpty, "no point uploading for a save that failed")
    }

    func testImageURLPersistFailureKeepsTheTextAndReportsIt() async throws {
        let host = FakeAnswerHost()
        let images = FakeAnswerImageStore()
        let subject = store(persister: FakeAnswerPersister(failingCalls: [2]), images: images)
        let plan = try XCTUnwrap(
            subject.plan(
                for: .fixture(["One", "", ""], images: [0: .pendingLocal(UIImage())]),
                baseline: .empty,
                questionId: questionId,
                in: host
            )
        )
        subject.applyOptimistically(plan, in: host)

        await subject.finish(plan, in: host)

        // The text did persist, so it stays; only the URL update is undone.
        XCTAssertEqual(host.normalized(questionId)?.texts, ["One", "", ""])
        XCTAssertEqual(host.normalized(questionId)?.urls, [nil, nil, nil])
        XCTAssertEqual(host.reported, [.imageURLSaveFailed])

        // The upload that succeeded before the URL write failed must not be orphaned: nothing
        // will ever reference it now that the cache reads as it did before this attempt.
        let deletedSlots = await images.deletedSlots
        XCTAssertEqual(deletedSlots, [0])
    }

    // MARK: - Orphaned images

    func testRemovedImageIsDeletedFromStorage() async throws {
        let images = FakeAnswerImageStore()
        let host = FakeAnswerHost()
        let subject = store(images: images)
        let baseline = NormalizedAnswer(
            texts: ["One", "Two", ""],
            urls: [nil, "https://example.com/gone.jpg", nil],
            attributions: [nil, nil, nil]
        )
        let plan = try XCTUnwrap(
            subject.plan(for: .fixture(["One", "Two", ""]), baseline: baseline, questionId: questionId, in: host)
        )
        subject.applyOptimistically(plan, in: host)

        await subject.finish(plan, in: host)

        let deletedSlots = await images.deletedSlots
        XCTAssertEqual(deletedSlots, [1])
    }

    func testKeptImageIsNotDeleted() async throws {
        let images = FakeAnswerImageStore()
        let host = FakeAnswerHost()
        let subject = store(images: images)
        let url = "https://example.com/kept.jpg"
        let baseline = NormalizedAnswer(
            texts: ["One", "", ""],
            urls: [url, nil, nil],
            attributions: [nil, nil, nil]
        )
        let plan = try XCTUnwrap(
            subject.plan(
                for: .fixture(["Edited", "", ""], images: [0: .saved(url: url, attribution: nil)]),
                baseline: baseline,
                questionId: questionId,
                in: host
            )
        )
        subject.applyOptimistically(plan, in: host)

        await subject.finish(plan, in: host)

        let deletedSlots = await images.deletedSlots
        XCTAssertTrue(deletedSlots.isEmpty)
    }

    // MARK: - The single entry point

    func testSaveReportsWhetherAnythingStarted() {
        let host = FakeAnswerHost()
        let subject = store()

        XCTAssertFalse(
            subject.save(.fixture(["", "", ""]), baseline: .empty, for: questionId, in: host),
            "an untouched editor saves nothing"
        )
        XCTAssertTrue(
            subject.save(.fixture(["One", "", ""]), baseline: .empty, for: questionId, in: host)
        )
    }
}
