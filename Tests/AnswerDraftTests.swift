import Testing
import UIKit
@testable import TTB

/// `AnswerDraft.isComplete` — the Complete Answer rule from `CONTEXT.md` — and the save tick's
/// ready-to-save predicate that combines it with `hasChanges(against:)`.
struct AnswerDraftTests {
    /// One slot's content, Sendable so it can parametrize a test. `SlotImage` holds a `UIImage`
    /// and is not Sendable, so the draft is built inside the test from these.
    enum SlotFixture: Sendable, CustomTestStringConvertible {
        case empty
        case text(String)
        case savedImage
        case pendingImage

        var slot: AnswerSlot {
            switch self {
            case .empty:
                .empty
            case let .text(text):
                AnswerSlot(text: text)
            case .savedImage:
                AnswerSlot(text: "", image: .saved(url: "https://example.com/a.jpg", attribution: nil))
            case .pendingImage:
                AnswerSlot(text: "", image: .pendingLocal(UIImage()))
            }
        }

        var testDescription: String {
            switch self {
            case .empty: "empty"
            case let .text(text): "text(\(text.debugDescription))"
            case .savedImage: "savedImage"
            case .pendingImage: "pendingImage"
            }
        }
    }

    private static func draft(_ fixtures: [SlotFixture]) -> AnswerDraft {
        AnswerDraft(fixtures.map(\.slot))
    }

    @Test(arguments: [
        [SlotFixture.text("Tea"), .text("Books"), .text("Rain")],
        [.text("Tea"), .savedImage, .text("Rain")],
        [.pendingImage, .savedImage, .text("  Rain ")],
    ])
    func everySlotFilledIsComplete(_ fixtures: [SlotFixture]) {
        #expect(Self.draft(fixtures).isComplete)
    }

    @Test(arguments: [
        [SlotFixture.text("Tea"), .text("Books"), .empty],
        [.text("Tea"), .text("Books"), .text("   \n\t")],
        [.empty, .empty, .empty],
    ])
    func anyUnfilledSlotIsIncomplete(_ fixtures: [SlotFixture]) {
        #expect(!Self.draft(fixtures).isComplete)
    }

    @Test func imageWithNoTextFillsTheSlot() {
        #expect(SlotFixture.savedImage.slot.isFilled)
        #expect(SlotFixture.pendingImage.slot.isFilled)
    }

    @Test func whitespaceOnlyTextDoesNotFillTheSlot() {
        #expect(!SlotFixture.text(" \n ").slot.isFilled)
    }

    @Test func unchangedSavedCompleteAnswerIsNotReadyToSave() {
        let saved = Self.draft([.text("Tea"), .savedImage, .text("Rain")])
        let baseline = saved.normalized()

        #expect(saved.isComplete)
        #expect(!(saved.isComplete && saved.hasChanges(against: baseline)))
    }

    @Test func editedSavedCompleteAnswerIsReadyToSave() {
        let saved = Self.draft([.text("Tea"), .savedImage, .text("Rain")])
        let baseline = saved.normalized()
        var edited = saved
        edited[2].text = "Rainy"

        #expect(edited.isComplete && edited.hasChanges(against: baseline))
    }
}
