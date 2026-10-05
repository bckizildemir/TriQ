import SwiftUI

struct OnboardingSharingComparisonCard: View {
  let question: String
  let leftTitle: String
  let leftAnswers: [String]
  let rightTitle: String
  let rightAnswers: [String]

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(question)
        .font(.headline)
        .foregroundStyle(.primary)
        .frame(maxWidth: .infinity, alignment: .leading)

      VStack(spacing: 0) {
        HStack(spacing: 0) {
          Text(leftTitle)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)

          Divider()
            .frame(height: 14)
            .padding(.horizontal, 8)

          Text(rightTitle)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.bottom, 6)

        ForEach(0..<3, id: \.self) { index in
          answerRow(index: index)
        }
      }
    }
    .padding()
    .frame(minHeight: 220)
    .background(
      RoundedRectangle(
        cornerRadius: QuestionCardLayoutMetrics.compactCornerRadius,
        style: .continuous
      )
      .fill(Color.theme.secondaryBackground)
    )
    .shadow(color: Color.black.opacity(0.08), radius: 2, x: 0, y: 1)
  }

  private func answerRow(index: Int) -> some View {
    VStack(spacing: 0) {
      HStack(alignment: .center, spacing: 0) {
        Text(answer(leftAnswers, at: index))
          .font(.subheadline)
          .foregroundStyle(answer(leftAnswers, at: index) == "-" ? .secondary : .primary)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.vertical, 6)

        Divider()
          .padding(.horizontal, 8)

        Text(answer(rightAnswers, at: index))
          .font(.subheadline)
          .foregroundStyle(answer(rightAnswers, at: index) == "-" ? .secondary : .primary)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.vertical, 6)
      }

      if index < 2 {
        Divider()
      }
    }
  }

  private func answer(_ answers: [String], at index: Int) -> String {
    guard index < answers.count else { return "-" }
    let value = answers[index].trimmingCharacters(in: .whitespacesAndNewlines)
    return value.isEmpty ? "-" : value
  }
}
