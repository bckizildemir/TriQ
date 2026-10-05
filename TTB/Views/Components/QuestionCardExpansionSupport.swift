import SwiftUI

enum QuestionCardLayoutMetrics {
    static let compactCornerRadius: CGFloat = 15
    static let compactContentPadding: CGFloat = 16
    static let minimumTapArea: CGFloat = 44
}

enum QuestionCardPresentationStyle: Equatable {
    case standard
    case pagedFeed
}

enum ExpandedQuestionHeaderStyle: Equatable {
    case plain
    case answered
    case mostAnswered(respondentCount: Int)

    var showsMatchedMeta: Bool {
        switch self {
        case .plain:
            false
        case .answered, .mostAnswered:
            true
        }
    }
}

struct ExpandedQuestionState: Identifiable {
    let question: Question
    let headerStyle: ExpandedQuestionHeaderStyle

    var id: String {
        question.id
    }
}

struct QuestionCardHeaderRow: View {
    let question: Question
    let headerStyle: ExpandedQuestionHeaderStyle

    private var localizedCategoryTitle: String {
        Question.localizedCategoryTitle(question.category)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Label(localizedCategoryTitle, systemImage: Question.categoryIconName(question.category))
                .font(.caption)
                .foregroundColor(.gray)
                .accessibilityLabel(
                    String(
                        format: String(localized: "question.card.categoryAccessibility"),
                        locale: AppLocalization.currentLocale,
                        localizedCategoryTitle
                    )
                )

            Spacer(minLength: 12)

            trailingContent
        }
    }

    @ViewBuilder
    private var trailingContent: some View {
        switch headerStyle {
        case .plain:
            EmptyView()
        case .answered:
            Text(question.answerTimeString)
                .font(.caption)
                .foregroundColor(.gray)
                .accessibilityLabel(
                    String(
                        format: String(localized: "question.card.answeredAccessibility"),
                        locale: AppLocalization.currentLocale,
                        question.answerTimeString
                    )
                )
        case .mostAnswered(let respondentCount):
            if respondentCount > 0 {
                HStack(spacing: 3) {
                    Image(systemName: "person.2.fill")
                        .font(.caption2)
                    Text("\(respondentCount)")
                        .font(.caption)
                }
                .foregroundColor(.gray)
                .accessibilityLabel(
                    String(
                        format: String(localized: "question.card.peopleAnsweredAccessibility"),
                        locale: AppLocalization.currentLocale,
                        respondentCount
                    )
                )
            }
        }
    }
}

struct QuestionCreatorAttributionView: View {
    enum Style {
        case plain
        case capsule
    }

    enum TextAlignment {
        case leading
        case center

        var frameAlignment: Alignment {
            switch self {
            case .leading:
                .leading
            case .center:
                .center
            }
        }

        var multilineTextAlignment: SwiftUI.TextAlignment {
            switch self {
            case .leading:
                .leading
            case .center:
                .center
            }
        }
    }

    let question: Question
    var style: Style = .plain
    var textAlignment: TextAlignment = .leading

    var body: some View {
        if let username = question.creatorAttributionUsername {
            attributionText(username: username)
        }
    }

    private func attributionText(username: String) -> some View {
        Text(
            String(
                format: String(localized: "question.creator.attribution"),
                locale: AppLocalization.currentLocale,
                username
            )
        )
        .font(.caption)
        .italic()
        .foregroundStyle(.secondary.opacity(0.72))
        .lineLimit(1)
        .truncationMode(.tail)
        .multilineTextAlignment(textAlignment.multilineTextAlignment)
        .frame(maxWidth: .infinity, alignment: textAlignment.frameAlignment)
        .padding(.horizontal, style == .capsule ? 10 : 0)
        .padding(.vertical, style == .capsule ? 0 : 0)
        .frame(height: style == .capsule ? 40 : nil, alignment: .center)
        .modifier(QuestionAttributionContainerModifier(style: style))
        .accessibilityLabel(
            String(
                format: String(localized: "question.creator.attributionAccessibility"),
                locale: AppLocalization.currentLocale,
                username
            )
        )
    }
}

private struct QuestionAttributionContainerModifier: ViewModifier {
    let style: QuestionCreatorAttributionView.Style

    func body(content: Content) -> some View {
        if style == .capsule {
            content.compactQuestionActionCapsuleStyle()
        } else {
            content
        }
    }
}

private struct CompactQuestionActionCapsuleModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .glassEffect(.regular.interactive(), in: .capsule)
        } else {
            content
                .background(.ultraThinMaterial, in: Capsule())
                .overlay {
                    Capsule()
                        .stroke(Color.theme.border.opacity(0.18), lineWidth: 1)
                }
                .contentShape(Capsule())
        }
    }
}

private struct CardToolbarIconButtonModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .buttonStyle(.glass)
        } else {
            content
                .buttonStyle(.plain)
                .background(.ultraThinMaterial, in: Circle())
                .overlay {
                    Circle()
                        .stroke(Color.theme.border.opacity(0.18), lineWidth: 1)
                }
                .contentShape(Circle())
        }
    }
}

extension View {
    func compactQuestionActionCapsuleStyle() -> some View {
        modifier(CompactQuestionActionCapsuleModifier())
    }

    func cardToolbarIconButtonStyle() -> some View {
        modifier(CardToolbarIconButtonModifier())
    }
}
