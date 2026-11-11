import Foundation

/// Remembers which answer slots the wand filled with AI text, so the AI notice shows only
/// while a slot still holds that text. An edit by the user removes the AI mark.
struct AIFilledAnswers: Equatable {
    private var texts: [Int: String] = [:]

    mutating func record(_ text: String, at index: Int) {
        texts[index] = text
    }

    /// True when at least one slot still holds the exact text the AI put there.
    func hasAIText(in currentTexts: [String]) -> Bool {
        texts.contains { index, text in
            currentTexts.indices.contains(index) && currentTexts[index] == text
        }
    }
}
