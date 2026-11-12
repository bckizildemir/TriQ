import SwiftUI

/// A quiet line that says the content next to it came from AI and can be wrong.
/// Place it only where AI content is on screen, never on an empty state.
struct AIGeneratedNotice: View {
    /// One case per AI surface; the raw value names the accessibility identifier.
    enum Surface: String, CaseIterable {
        case quickAnswers = "quick-answers"
        case wandFill = "wand-fill"
        case trioIdeas = "trio-ideas"
        case trioCategory = "trio-category"
        case queryCard = "query-card"
        case queryDetail = "query-detail"
        case queryResult = "query-result"

        var accessibilityIdentifier: String { "ai-notice-\(rawValue)" }
    }

    let surface: Surface

    var body: some View {
        Label {
            Text(String(localized: "ai.notice.generated"))
        } icon: {
            Image(systemName: "sparkles")
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(surface.accessibilityIdentifier)
    }
}

#Preview {
    AIGeneratedNotice(surface: .quickAnswers)
        .padding()
}
