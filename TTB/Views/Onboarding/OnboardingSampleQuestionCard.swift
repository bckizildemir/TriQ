import SwiftUI

struct OnboardingSampleQuestionCard: View {
  let question: String
  let answers: [String]
  let symbols: [String]
  var categoryColor: Color = .accentColor

  private let thumbnailSize: CGFloat = 48
  private let badgeSize: CGFloat = 26
  private let slotCornerRadius: CGFloat = 18
  private let compactActionButtonSize: CGFloat = 30

  var body: some View {
    ZStack(alignment: .bottom) {
      cardContent
        .padding(.bottom, 54)

      decorativeFooter
        .padding(.horizontal, QuestionCardLayoutMetrics.compactContentPadding)
        .padding(.bottom, 10)
    }
    .background(
      RoundedRectangle(
        cornerRadius: QuestionCardLayoutMetrics.compactCornerRadius,
        style: .continuous
      )
      .fill(Color.theme.secondaryBackground)
    )
    .shadow(color: Color.black.opacity(0.08), radius: 2, x: 0, y: 1)
  }

  private var cardContent: some View {
    VStack(alignment: .leading, spacing: 18) {
      Text(question)
        .font(.headline)
        .foregroundStyle(Color.theme.text)
        .lineLimit(3)
        .multilineTextAlignment(.leading)
        .frame(maxWidth: .infinity, alignment: .leading)

      VStack(spacing: 8) {
        ForEach(Array(answers.enumerated()), id: \.offset) { index, answer in
          answerSlotRow(index: index, text: answer, symbol: symbol(at: index))
        }
      }
    }
    .padding(QuestionCardLayoutMetrics.compactContentPadding)
  }

  private func answerSlotRow(index: Int, text: String, symbol: String) -> some View {
    HStack(alignment: .center, spacing: 10) {
      Text("\(index + 1)")
        .font(.caption.weight(.bold))
        .foregroundStyle(categoryColor)
        .frame(width: badgeSize, height: badgeSize)
        .background(Color(uiColor: .tertiarySystemBackground), in: Circle())
        .overlay {
          Circle()
            .stroke(Color.theme.border.opacity(0.18), lineWidth: 1)
        }
        .accessibilityHidden(true)

      Text(text)
        .font(.subheadline)
        .foregroundStyle(.primary)
        .lineLimit(2)
        .multilineTextAlignment(.leading)
        .frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)

      symbolThumbnail(symbol)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 10)
    .background(
      RoundedRectangle(cornerRadius: slotCornerRadius)
        .fill(Color(uiColor: .secondarySystemBackground))
    )
    .overlay {
      RoundedRectangle(cornerRadius: slotCornerRadius)
        .stroke(Color.theme.border.opacity(0.12), lineWidth: 1)
    }
  }

  private func symbolThumbnail(_ symbol: String) -> some View {
    Image(systemName: symbol)
      .font(.title3)
      .foregroundStyle(categoryColor)
      .frame(width: thumbnailSize, height: thumbnailSize)
      .background(Color(uiColor: .tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
      .overlay {
        RoundedRectangle(cornerRadius: 12)
          .stroke(Color.theme.border.opacity(0.12), lineWidth: 1)
      }
  }

  private var decorativeFooter: some View {
    HStack {
      Spacer()

      HStack(spacing: 2) {
        decorativeIcon("bookmark")
        decorativeIcon("square.and.arrow.up")
        decorativeIcon("star.fill", color: .yellow)
      }
      .padding(.horizontal, 7)
      .padding(.vertical, 5)
      .compactQuestionActionCapsuleStyle()
      .allowsHitTesting(false)
      .accessibilityHidden(true)
    }
  }

  private func decorativeIcon(_ systemName: String, color: Color = .gray) -> some View {
    Image(systemName: systemName)
      .font(.body)
      .foregroundStyle(color)
      .frame(width: compactActionButtonSize, height: compactActionButtonSize)
  }

  private func symbol(at index: Int) -> String {
    guard index < symbols.count else { return "photo" }
    return symbols[index]
  }
}
