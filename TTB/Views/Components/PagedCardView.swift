import Nuke
import SwiftUI

// MARK: - Page Indicator

struct PageIndicator: View {
  let count: Int
  let current: Int

  private let maxVisibleDots = 9
  private let activeDotSize: CGFloat = 8
  private let defaultDotSize: CGFloat = 6
  private let mediumEdgeDotSize: CGFloat = 5
  private let smallEdgeDotSize: CGFloat = 4

  var body: some View {
    HStack(spacing: 6) {
      ForEach(visibleRange, id: \.self) { index in
        Circle()
          .fill(index == current ? Color.primary : Color.secondary.opacity(0.4))
          .frame(width: dotSize(for: index), height: dotSize(for: index))
          .animation(.spring(response: 0.3, dampingFraction: 0.7), value: current)
      }
    }
    .frame(height: activeDotSize)
    .accessibilityElement()
    .accessibilityLabel(
      String(
        format: String(localized: "paged.pageIndicator"),
        locale: AppLocalization.currentLocale,
        current + 1,
        count
      )
    )
  }

  private var visibleRange: Range<Int> {
    guard count > maxVisibleDots else { return 0..<count }

    let halfWindow = maxVisibleDots / 2
    let lowerBound = min(max(current - halfWindow, 0), count - maxVisibleDots)

    return lowerBound..<(lowerBound + maxVisibleDots)
  }

  private func dotSize(for index: Int) -> CGFloat {
    guard index != current else { return activeDotSize }
    guard count > maxVisibleDots else { return defaultDotSize }

    let distanceFromVisibleStart = index - visibleRange.lowerBound
    let distanceFromVisibleEnd = visibleRange.upperBound - 1 - index
    let edgeDistance = min(distanceFromVisibleStart, distanceFromVisibleEnd)

    switch edgeDistance {
    case 0:
      return smallEdgeDotSize
    case 1:
      return mediumEdgeDotSize
    default:
      return defaultDotSize
    }
  }
}

private struct QuestionCardHeightPreferenceKey: PreferenceKey {
  static let defaultValue: [String: CGFloat] = [:]

  static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) {
    value.merge(nextValue(), uniquingKeysWith: { _, new in new })
  }
}

// MARK: - PagedCardView

/// A reusable paged (Instagram-style) card list.
/// Each card fills the available width; users swipe horizontally to paginate.
struct PagedCardView: View {
  let questions: [Question]
  let model: QuestionModel
  var sourceID: String = "default"
  var badgeModel: BadgeModel? = nil
  var onQuestionTap: ((Question) -> Void)?
  var selectedQuestionID: String?
  /// When false, images are hidden even if data is available (e.g. MostAnswered).
  var showImages: Bool = true
  var showsShareButton: Bool = false
  var maximumCardHeight: CGFloat? = nil
  var cardPresentationStyle: QuestionCardPresentationStyle = .pagedFeed
  var categoryColor: Color = .accentColor

  @State private var currentPage: Int = 0
  @State private var prefetcher = ImagePrefetcher()
  @State private var measuredCardHeights: [String: CGFloat] = [:]

  var body: some View {
    if questions.isEmpty {
      EmptyView()
    } else {
      VStack(spacing: 10) {
        pagedTabView
        if questions.count > 1 {
          PageIndicator(count: questions.count, current: currentPage)
            .padding(.top, 2)
        }
      }
    }
  }

  @ViewBuilder
  private var pagedTabView: some View {
    GeometryReader { geometry in
      TabView(selection: $currentPage) {
        ForEach(Array(questions.enumerated()), id: \.element.id) { index, question in
          QuestionCard(
            question: question,
            model: model,
            sourceID: sourceID,
            onTap: onQuestionTap != nil ? { onQuestionTap?(question) } : nil,
            isSelected: selectedQuestionID == question.id,
            showImages: showImages,
            showsShareButton: showsShareButton,
            badgeModel: badgeModel,
            presentationStyle: cardPresentationStyle,
            maximumPreviewHeight: maximumCardHeight,
            categoryColor: categoryColor
          )
          .fixedSize(horizontal: false, vertical: true)
          .background {
            GeometryReader { cardGeometry in
              Color.clear.preference(
                key: QuestionCardHeightPreferenceKey.self,
                value: [question.id: cardGeometry.size.height]
              )
            }
          }
          // Side padding so the next card peeks through on the right
          .padding(.horizontal, 4)
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
          .tag(index)
        }
      }
      .tabViewStyle(.page(indexDisplayMode: .never))
      .frame(width: geometry.size.width)
    }
    .frame(height: resolvedCardHeight)
    .animation(.spring(response: 0.35, dampingFraction: 0.85), value: resolvedCardHeight)
    .onPreferenceChange(QuestionCardHeightPreferenceKey.self) { heights in
      measuredCardHeights.merge(heights, uniquingKeysWith: { _, new in new })
    }
    .onAppear { prefetchImages(around: currentPage) }
    .onChange(of: currentPage) { _, newPage in prefetchImages(around: newPage) }
  }

  private func prefetchImages(around page: Int) {
    guard showImages else { return }
    let lower = max(0, page - 1)
    let upper = min(questions.count - 1, page + 2)
    guard lower <= upper else { return }
    let urls = (lower...upper).flatMap { i in
      model.myImageURLs(for: questions[i].id)
        .compactMap { $0.flatMap(URL.init) }
    }
    guard !urls.isEmpty else { return }
    prefetcher.startPrefetching(with: urls)
  }

  private var resolvedCardHeight: CGFloat {
    let measuredHeight = activeQuestion.flatMap { measuredCardHeights[$0.id] } ?? fallbackCardHeight
    return clampedCardHeight(measuredHeight)
  }

  private var fallbackCardHeight: CGFloat {
    clampedCardHeight(380)
  }

  private var activeQuestion: Question? {
    guard questions.indices.contains(currentPage) else { return questions.first }
    return questions[currentPage]
  }

  private func clampedCardHeight(_ height: CGFloat) -> CGFloat {
    guard let maximumCardHeight else { return height }
    return min(height, maximumCardHeight)
  }
}

#Preview {
  PagedCardView(
    questions: Question.sampleQuestions,
    model: QuestionModel()
  )
  .padding(.horizontal)
  .environmentObject(AuthModel())
  .environmentObject(FavoriteStore.previews)
  .environmentObject(GuestFavoriteModel())
}
