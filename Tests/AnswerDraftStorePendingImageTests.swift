import Foundation
import Testing
import UIKit
@testable import TTB

/// The Home card shows a picked image at once, from what the device already has.
@MainActor
struct AnswerDraftStorePendingImageTests {
    private let questionId = "q-1"

    private func store(
        persister: FakeAnswerPersister = FakeAnswerPersister(),
        images: FakeAnswerImageStore = FakeAnswerImageStore()
    ) -> AnswerDraftStore {
        AnswerDraftStore(persister: persister, images: images)
    }

    private func suggestion() -> AnswerImageSuggestion {
        AnswerImageSuggestion(
            id: "s1",
            photoId: "p1",
            thumbnailURL: "https://images.pexels.com/t.jpg",
            previewURL: "https://images.pexels.com/p.jpg",
            fullSizeURL: "https://images.pexels.com/f.jpg",
            photographer: "Ada",
            photographerURL: "https://pexels.com/@ada",
            photoURL: "https://pexels.com/p1"
        )
    }

    @Test func libraryPickShowsOnTheCardTheMomentSaveReturns() {
        let host = FakeAnswerHost()
        let picked = UIImage()

        let started = store().save(
            .fixture(["a", "", ""], images: [0: .pendingLocal(picked)]),
            baseline: .empty,
            for: questionId,
            in: host
        )

        #expect(started)
        #expect(host.pendingImages[questionId]?[0] === picked)
        #expect(host.normalized(questionId)?.urls == [nil, nil, nil])
    }

    @Test func suggestionUsesThePreviewTheEditorLoaded() {
        let host = FakeAnswerHost()
        let loaded = UIImage()

        store().save(
            .fixture(["a", "", ""], images: [0: .pendingSuggestion(suggestion())]),
            baseline: .empty,
            for: questionId,
            previewImages: [0: loaded],
            in: host
        )

        #expect(host.pendingImages[questionId]?[0] === loaded)
    }

    @Test func suggestionWithoutALoadedPreviewHoldsNothing() {
        let host = FakeAnswerHost()

        store().save(
            .fixture(["a", "", ""], images: [0: .pendingSuggestion(suggestion())]),
            baseline: .empty,
            for: questionId,
            in: host
        )

        #expect(host.pendingSlots(questionId).isEmpty)
    }

    @Test func uploadedSlotKeepsItsImageUntilTheCardReleasesIt() async throws {
        let host = FakeAnswerHost()
        let store = store()
        let plan = try #require(store.plan(
            for: .fixture(["a", "", ""], images: [0: .pendingLocal(UIImage())]),
            baseline: .empty,
            questionId: questionId,
            in: host
        ))
        store.applyOptimistically(plan, in: host)

        await store.finish(plan, in: host)

        #expect(host.pendingSlots(questionId) == [0])
        #expect(host.normalized(questionId)?.urls[0] != nil)
    }

    @Test func failedUploadReleasesOnlyThatSlot() async throws {
        let host = FakeAnswerHost()
        let store = store(images: FakeAnswerImageStore(failingSlots: [0]))
        let plan = try #require(store.plan(
            for: .fixture(
                ["a", "b", ""],
                images: [0: .pendingLocal(UIImage()), 1: .pendingLocal(UIImage())]
            ),
            baseline: .empty,
            questionId: questionId,
            in: host
        ))
        store.applyOptimistically(plan, in: host)

        await store.finish(plan, in: host)

        #expect(host.pendingSlots(questionId) == [1])
        #expect(host.reported.count == 1)
    }

    @Test func textSaveFailureRollsTheImageBack() async throws {
        let host = FakeAnswerHost()
        let store = store(persister: FakeAnswerPersister(failingCalls: [1]))
        let plan = try #require(store.plan(
            for: .fixture(["a", "", ""], images: [0: .pendingLocal(UIImage())]),
            baseline: .empty,
            questionId: questionId,
            in: host
        ))
        store.applyOptimistically(plan, in: host)

        await store.finish(plan, in: host)

        #expect(host.pendingSlots(questionId).isEmpty)
        #expect(host.reported == [.textSaveFailed])
    }

    @Test func imageURLSaveFailureReleasesTheImages() async throws {
        let host = FakeAnswerHost()
        let store = store(persister: FakeAnswerPersister(failingCalls: [2]))
        let plan = try #require(store.plan(
            for: .fixture(["a", "", ""], images: [0: .pendingLocal(UIImage())]),
            baseline: .empty,
            questionId: questionId,
            in: host
        ))
        store.applyOptimistically(plan, in: host)

        await store.finish(plan, in: host)

        #expect(host.pendingSlots(questionId).isEmpty)
        #expect(host.reported == [.imageURLSaveFailed])
    }

    @Test func nextSaveDropsImagesItDoesNotUpload() {
        let host = FakeAnswerHost()
        let store = store()
        store.save(
            .fixture(["a", "", ""], images: [0: .pendingLocal(UIImage())]),
            baseline: .empty,
            for: questionId,
            in: host
        )
        let afterFirst = host.normalized(questionId) ?? .empty

        store.save(
            .fixture(["a", "b", ""]),
            baseline: afterFirst,
            for: questionId,
            in: host
        )

        #expect(host.pendingSlots(questionId).isEmpty)
    }
}
