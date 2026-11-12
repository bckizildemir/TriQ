import Foundation
import Testing
@testable import TTB

struct AIGeneratedNoticeTests {
    @Test func everySurfaceHasAUniquePrefixedIdentifier() {
        let identifiers = AIGeneratedNotice.Surface.allCases.map(\.accessibilityIdentifier)

        #expect(Set(identifiers).count == identifiers.count)
        #expect(identifiers.allSatisfy { $0.hasPrefix("ai-notice-") })
        #expect(AIGeneratedNotice.Surface.quickAnswers.accessibilityIdentifier == "ai-notice-quick-answers")
    }

    @Test func wandTextCountsWhileTheSlotStillHoldsIt() {
        var filled = AIFilledAnswers()
        #expect(!filled.hasAIText(in: ["", "", ""]))

        filled.record("Pizza", at: 1)
        #expect(filled.hasAIText(in: ["", "Pizza", ""]))
    }

    @Test func editingTheWandTextRemovesTheNotice() {
        var filled = AIFilledAnswers()
        filled.record("Pizza", at: 1)

        #expect(!filled.hasAIText(in: ["", "Pizza!", ""]))
        #expect(!filled.hasAIText(in: ["Pizza", "", ""]))
    }

    @Test func oneUntouchedSlotKeepsTheNotice() {
        var filled = AIFilledAnswers()
        filled.record("Pizza", at: 0)
        filled.record("Sushi", at: 2)

        #expect(filled.hasAIText(in: ["Pizza", "x", "Sushi edited"]))
    }
}
