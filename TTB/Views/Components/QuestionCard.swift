import NukeUI
import SwiftUI

struct QuestionCard: View {
  let question: Question
  @ObservedObject var model: QuestionModel
  var headerStyle: ExpandedQuestionHeaderStyle = .plain
  var sourceID: String = "default"
  var onTap: (() -> Void)?
  var isSelected: Bool = false
  // When false, images are hidden even if data is available (e.g. MostAnswered)
  var showImages: Bool = true
  var showsShareButton: Bool = false
  var badgeModel: BadgeModel? = nil
  var presentationStyle: QuestionCardPresentationStyle = .standard
  var maximumPreviewHeight: CGFloat? = nil
  var categoryColor: Color = .accentColor

  @EnvironmentObject private var authModel: AuthModel
  @EnvironmentObject private var favoriteStore: FavoriteStore
  @EnvironmentObject private var guestFavoriteModel: GuestFavoriteModel
  @EnvironmentObject private var questionListStore: QuestionListStore
  @Environment(\.toastCenter) private var toastCenter

  @State private var isShowingQuestionLists = false

  private var isFavorite: Bool {
    favoriteStore.state(of: question)
  }

  private var questionAccessibilityLabel: String {
    String(
      format: String(localized: "question.card.accessibilityLabel"),
      locale: AppLocalization.currentLocale,
      question.text
    )
  }

  private var primaryAccessibilityHint: String {
    String(localized: onTap != nil ? "question.card.expandHint" : "question.card.openHint")
  }

  private var favoriteAccessibilityLabel: String {
    String(localized: isFavorite ? "common.favorite.remove" : "common.favorite.add")
  }

  private var isInQuestionList: Bool {
    questionListStore.isQuestionInAnyList(question.id)
  }

  private var questionListAccessibilityLabel: String {
    String(localized: isInQuestionList ? "question.card.lists.manageSaved" : "question.card.lists.add")
  }

  var body: some View {
    ZStack(alignment: .bottom) {
      primarySurface

      cardFooter
        .padding(.horizontal, QuestionCardLayoutMetrics.compactContentPadding)
        .padding(.bottom, QuestionCardLayoutMetrics.compactContentPadding)
    }
    .opacity(isSelected ? 0 : 1)
    .allowsHitTesting(!isSelected)
    .accessibilityElement(children: .contain)
    .sheet(isPresented: $isShowingQuestionLists) {
      QuestionListSelectionSheet(question: question)
    }
  }

  @ViewBuilder
  private var primarySurface: some View {
    if let onTap = onTap {
      Button(action: onTap) {
        cardContent
      }
      .buttonStyle(.plain)
      .contentShape(Rectangle())
      .accessibilityIdentifier("question-card-\(sourceID)-\(question.id)")
      .accessibilityLabel(questionAccessibilityLabel)
      .accessibilityHint(primaryAccessibilityHint)
      .accessibilitySortPriority(1)
    } else {
      NavigationLink(
        destination: QuestionDetailView(question: question, model: model, badgeModel: badgeModel)
      ) {
        cardContent
      }
      .buttonStyle(.plain)
      .contentShape(Rectangle())
      .accessibilityIdentifier("question-card-\(sourceID)-\(question.id)")
      .accessibilityLabel(questionAccessibilityLabel)
      .accessibilityHint(primaryAccessibilityHint)
      .accessibilitySortPriority(1)
    }
  }

  @ViewBuilder
  private var cardContent: some View {
    Group {
      switch presentationStyle {
      case .standard:
        standardCardContent
      case .pagedFeed:
        compactPagedFeedContent
      }
    }
    .contentShape(Rectangle())
  }

  private var standardCardContent: some View {
    ZStack {
      cardBackground

      mainCardContent
      .padding(QuestionCardLayoutMetrics.compactContentPadding)
    }
    .contentShape(RoundedRectangle(cornerRadius: QuestionCardLayoutMetrics.compactCornerRadius))
    .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
  }

  private var compactPagedFeedContent: some View {
    ZStack {
      cardBackground

      mainCardContent
      .padding(QuestionCardLayoutMetrics.compactContentPadding)
    }
    .contentShape(RoundedRectangle(cornerRadius: QuestionCardLayoutMetrics.compactCornerRadius))
    .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
  }

  @ViewBuilder
  private var mainCardContent: some View {
    VStack(alignment: .leading, spacing: 0) {
      if headerStyle != .plain {
        metaRow
        Spacer()
          .frame(height: headerToTitleSpacing)
      }

      titleText

      Spacer()
        .frame(height: titleToAnswerSpacing)

      answerPreviews

      Spacer()
        .frame(height: answerToFavoriteSpacing)

      favoriteButtonReservation
    }
  }

  private var metaRow: some View {
    QuestionCardHeaderRow(question: question, headerStyle: headerStyle)
  }

  private var titleText: some View {
    Text(question.text)
      .font(.headline)
      .lineLimit(titleLineLimit)
      .multilineTextAlignment(.center)
      .frame(maxWidth: .infinity, alignment: .center)
      .foregroundColor(.primary)
  }

  @ViewBuilder
  private var answerPreviews: some View {
    let userAnswers = model.myAnswers(for: question.id)
    let userImageURLs = showImages ? model.myImageURLs(for: question.id) : [nil, nil, nil]

    VStack(alignment: .leading, spacing: answerSlotSpacing) {
      ForEach(0..<3, id: \.self) { index in
        let answer = index < userAnswers.count ? userAnswers[index] : ""
        let placeholder = Question.answerPlaceholders[index]
        let imageURL: String? = index < userImageURLs.count ? userImageURLs[index] : nil

        if presentationStyle == .pagedFeed {
          answerSlotRow(index: index, text: answer, placeholder: placeholder, imageURL: imageURL)
        } else {
          VStack(alignment: .leading, spacing: answerSlotImageSpacing) {
            answerSlotRow(index: index, text: answer, placeholder: placeholder)
            if let urlString = imageURL, let url = URL(string: urlString) {
              answerPreviewImage(for: url, maxHeight: answerPreviewImageMaxHeight(for: userImageURLs))
            }
          }
        }
      }
    }
  }

  private func answerSlotRow(index: Int, text: String, placeholder: String, imageURL: String? = nil) -> some View {
    let isEmpty = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

    return HStack(alignment: .center, spacing: answerSlotBadgeSpacing) {
      Text("\(index + 1)")
        .font(.caption.weight(.bold))
        .foregroundStyle(categoryColor)
        .frame(width: answerSlotBadgeSize, height: answerSlotBadgeSize)
        .background(Color(uiColor: .tertiarySystemBackground), in: Circle())
        .overlay {
          Circle()
            .stroke(Color.theme.border.opacity(0.18), lineWidth: 1)
        }
        .accessibilityHidden(true)

      Text(isEmpty ? placeholder : text)
        .font(.subheadline)
        .foregroundStyle(isEmpty ? Color.secondary.opacity(0.68) : Color.primary)
        .lineLimit(answerLineLimit)
        .multilineTextAlignment(.leading)
        .frame(maxWidth: .infinity, minHeight: answerSlotTextMinHeight, alignment: .leading)

      if let urlString = imageURL, let url = URL(string: urlString) {
        answerPreviewThumbnail(for: url)
      }
    }
    .padding(.horizontal, answerSlotHorizontalPadding)
    .padding(.vertical, answerSlotVerticalPadding)
    .background(
      RoundedRectangle(cornerRadius: answerSlotCornerRadius)
        .fill(Color(uiColor: .secondarySystemBackground))
    )
    .overlay {
      RoundedRectangle(cornerRadius: answerSlotCornerRadius)
        .stroke(Color.theme.border.opacity(0.12), lineWidth: 1)
    }
  }

  private var favoriteButtonReservation: some View {
    HStack(alignment: .center, spacing: 12) {
      Color.clear
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)

      Color.clear
        .frame(width: actionCapsuleReservedWidth)
        .accessibilityHidden(true)
    }
    .frame(height: favoriteButtonReservationHeight)
  }

  private var cardFooter: some View {
    HStack(alignment: .center, spacing: 10) {
      QuestionCreatorAttributionView(question: question, style: .capsule)
        .frame(maxWidth: .infinity, alignment: .leading)
        .layoutPriority(1)

      actionCapsule
        .fixedSize()
    }
    .frame(height: favoriteButtonReservationHeight)
  }

  private var actionCapsule: some View {
    HStack(spacing: 2) {
      if showsShareButton {
        shareButton
      }
      questionListButton
      favoriteButton
    }
    .padding(.horizontal, 7)
    .padding(.vertical, 5)
    .compactQuestionActionCapsuleStyle()
  }

  private var questionListButton: some View {
    Button {
      if authModel.isAnonymous {
        guestFavoriteModel.requestGuestUpgrade()
      } else {
        isShowingQuestionLists = true
      }
    } label: {
      Label(questionListAccessibilityLabel, systemImage: isInQuestionList ? "bookmark.fill" : "bookmark")
        .labelStyle(.iconOnly)
        .foregroundStyle(isInQuestionList ? Color.accentColor : .gray)
        .frame(
          width: compactActionButtonSize,
          height: compactActionButtonSize
        )
        .contentShape(Rectangle())
    }
    .accessibilityLabel(questionListAccessibilityLabel)
    .accessibilityIdentifier("question-card-list-\(sourceID)-\(question.id)")
    .buttonStyle(.plain)
  }

  private var favoriteButton: some View {
    Button {
      toggleFavorite()
    } label: {
      Label(favoriteAccessibilityLabel, systemImage: isFavorite ? "star.fill" : "star")
        .labelStyle(.iconOnly)
        .foregroundStyle(isFavorite ? .yellow : .gray)
        .animation(.easeInOut(duration: 0.2), value: isFavorite)
        .frame(
          width: compactActionButtonSize,
          height: compactActionButtonSize
        )
        .contentShape(Rectangle())
    }
    .accessibilityLabel(favoriteAccessibilityLabel)
    .accessibilityIdentifier("question-card-favorite-\(sourceID)-\(question.id)")
    .buttonStyle(.plain)
  }

  private func toggleFavorite() {
    Task {
      await toastCenter.toggleFavorite(question, using: favoriteStore)
    }
  }

  private var shareButton: some View {
    ShareLink(item: question.shareURL) {
      Label(String(localized: "common.share"), systemImage: "square.and.arrow.up")
        .labelStyle(.iconOnly)
        .foregroundStyle(.gray)
        .frame(
          width: compactActionButtonSize,
          height: compactActionButtonSize
        )
        .contentShape(Rectangle())
    }
    .accessibilityLabel(String(localized: "common.share"))
    .accessibilityIdentifier("question-card-share-\(sourceID)-\(question.id)")
    .buttonStyle(.plain)
  }

  private var cardBackground: some View {
    RoundedRectangle(cornerRadius: QuestionCardLayoutMetrics.compactCornerRadius)
      .fill(Color.theme.secondaryBackground)
  }

  private var titleLineLimit: Int? {
    presentationStyle == .pagedFeed ? 3 : nil
  }

  private var answerLineLimit: Int? {
    presentationStyle == .pagedFeed ? 2 : nil
  }

  private var headerToTitleSpacing: CGFloat {
    presentationStyle == .pagedFeed ? 12 : 14
  }

  private var titleToAnswerSpacing: CGFloat {
    presentationStyle == .pagedFeed ? 18 : 20
  }

  private var answerToFavoriteSpacing: CGFloat {
    presentationStyle == .pagedFeed ? 24 : 24
  }

  private var favoriteButtonReservationHeight: CGFloat {
    42
  }

  private var compactActionButtonSize: CGFloat {
    30
  }

  private var actionCapsuleReservedWidth: CGFloat {
    CGFloat(showsShareButton ? 3 : 2) * compactActionButtonSize
      + CGFloat(showsShareButton ? 2 : 1) * 2
      + 14
  }

  private var answerSlotSpacing: CGFloat {
    presentationStyle == .pagedFeed ? 8 : 10
  }

  private var answerSlotImageSpacing: CGFloat {
    presentationStyle == .pagedFeed ? 6 : 8
  }

  private var answerSlotBadgeSpacing: CGFloat {
    presentationStyle == .pagedFeed ? 10 : 12
  }

  private var answerSlotHorizontalPadding: CGFloat {
    presentationStyle == .pagedFeed ? 12 : 14
  }

  private var answerSlotVerticalPadding: CGFloat {
    presentationStyle == .pagedFeed ? 10 : 12
  }

  private var answerSlotTextMinHeight: CGFloat {
    presentationStyle == .pagedFeed ? 24 : 30
  }

  private var answerSlotBadgeSize: CGFloat {
    presentationStyle == .pagedFeed ? 26 : 28
  }

  private var answerSlotCornerRadius: CGFloat {
    presentationStyle == .pagedFeed ? 18 : 20
  }

  private func answerPreviewImageMaxHeight(for imageURLs: [String?]) -> CGFloat {
    guard presentationStyle == .pagedFeed else { return 160 }

    let visibleImageCount = imageURLs.filter { $0?.isEmpty == false }.count
    guard visibleImageCount > 0 else { return 120 }

    let reservedNonImageHeight: CGFloat = 390
    let imageMinHeight: CGFloat = 44
    let imageMaxHeight: CGFloat = 96
    let availableHeight = (maximumPreviewHeight ?? 380) - reservedNonImageHeight
    let perImageHeight = max(imageMinHeight, availableHeight / CGFloat(visibleImageCount))
    return min(imageMaxHeight, perImageHeight)
  }

  @ViewBuilder
  private func answerPreviewImage(for url: URL, maxHeight: CGFloat) -> some View {
    LazyImage(url: url) { state in
      if let uiImage = state.imageContainer?.image {
        answerPreviewLoadedImage(uiImage, maxHeight: maxHeight)
      } else if state.error != nil {
        EmptyView()
      } else {
        RoundedRectangle(cornerRadius: 14)
          .fill(Color.secondary.opacity(0.15))
          .frame(maxWidth: .infinity)
          .frame(height: maxHeight)
          .overlay(ProgressView())
      }
    }
  }

  private func answerPreviewLoadedImage(_ uiImage: UIImage, maxHeight: CGFloat) -> some View {
    let aspect = uiImage.size.width / uiImage.size.height
    let displayHeight = min(uiImage.size.height, maxHeight)
    let displayWidth = displayHeight * aspect

    return Image(uiImage: uiImage)
      .resizable()
      .frame(width: displayWidth, height: displayHeight)
      .clipShape(RoundedRectangle(cornerRadius: 14))
      .frame(maxWidth: .infinity, alignment: .center)
  }

  @ViewBuilder
  private func answerPreviewThumbnail(for url: URL) -> some View {
    LazyImage(url: url) { state in
      if let image = state.image {
        image
          .resizable()
          .scaledToFill()
          .frame(width: answerPreviewThumbnailSize, height: answerPreviewThumbnailSize)
          .clipShape(RoundedRectangle(cornerRadius: 12))
      } else if state.error != nil {
        EmptyView()
      } else {
        RoundedRectangle(cornerRadius: 12)
          .fill(Color.secondary.opacity(0.15))
          .frame(width: answerPreviewThumbnailSize, height: answerPreviewThumbnailSize)
          .overlay {
            ProgressView()
              .scaleEffect(0.7)
          }
      }
    }
  }

  private var answerPreviewThumbnailSize: CGFloat {
    48
  }
}

struct QuestionCard_Previews: PreviewProvider {
  static var previews: some View {
    NavigationView {
      QuestionCard(
        question: Question.sampleQuestions[0],
        model: QuestionModel(localQuestions: Question.sampleQuestions)
      )
      .previewLayout(.sizeThatFits)
      .padding()
    }
    .environmentObject(AuthModel())
    .environmentObject(FavoriteStore.previews)
    .environmentObject(GuestFavoriteModel())
  }
}
