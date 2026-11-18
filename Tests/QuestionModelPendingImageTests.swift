import Testing
import UIKit
@testable import TTB

/// `QuestionModel` is the real host of the images held while an answer's upload runs.
@MainActor
struct QuestionModelPendingImageTests {
    private let questionId = "q-1"

    @Test func holdsImagesBySlot() {
        let model = QuestionModel(localQuestions: [])
        let first = UIImage()
        let third = UIImage()

        model.setPendingImages([0: first, 2: third], for: questionId)

        let held = model.myPendingImages(for: questionId)
        #expect(held.count == AnswerDraft.slotCount)
        #expect(held[0] === first)
        #expect(held[1] == nil)
        #expect(held[2] === third)
    }

    @Test func unknownQuestionHoldsNothing() {
        let model = QuestionModel(localQuestions: [])

        #expect(model.myPendingImages(for: "nope").allSatisfy { $0 == nil })
    }

    @Test func settingReplacesTheWholeSet() {
        let model = QuestionModel(localQuestions: [])
        model.setPendingImages([0: UIImage(), 1: UIImage()], for: questionId)

        model.setPendingImages([2: UIImage()], for: questionId)

        let held = model.myPendingImages(for: questionId)
        #expect(held[0] == nil)
        #expect(held[1] == nil)
        #expect(held[2] != nil)
    }

    @Test func emptySetClearsTheQuestion() {
        let model = QuestionModel(localQuestions: [])
        model.setPendingImages([0: UIImage()], for: questionId)

        model.setPendingImages([:], for: questionId)

        #expect(model.pendingAnswerImages[questionId] == nil)
    }

    @Test func releasingOneSlotKeepsTheOthers() {
        let model = QuestionModel(localQuestions: [])
        let kept = UIImage()
        model.setPendingImages([0: UIImage(), 1: kept], for: questionId)

        model.releasePendingImage(slotIndex: 0, for: questionId)

        let held = model.myPendingImages(for: questionId)
        #expect(held[0] == nil)
        #expect(held[1] === kept)
    }

    @Test func releasingTheLastSlotDropsTheQuestionEntry() {
        let model = QuestionModel(localQuestions: [])
        model.setPendingImages([1: UIImage()], for: questionId)

        model.releasePendingImage(slotIndex: 1, for: questionId)

        #expect(model.pendingAnswerImages[questionId] == nil)
    }

    @Test func releasingAnEmptySlotIsHarmless() {
        let model = QuestionModel(localQuestions: [])

        model.releasePendingImage(slotIndex: 0, for: questionId)

        #expect(model.pendingAnswerImages.isEmpty)
    }

    @Test func clearingRemoteStateDropsHeldImages() {
        let model = QuestionModel(localQuestions: [])
        model.setPendingImages([0: UIImage()], for: questionId)

        model.clearRemoteState()

        #expect(model.pendingAnswerImages.isEmpty)
    }
}
