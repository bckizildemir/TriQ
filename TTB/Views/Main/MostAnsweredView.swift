import SwiftUI

// MARK: - Data model for the leaderboard list

struct MostAnsweredItem: Identifiable {
    var id: String { question.id }
    let question: Question
    /// Current user's own answers loaded from the userAnswers subcollection.
    /// Empty array when the user has not answered this question yet.
    let userAnswers: [String]
    /// Current user's image URLs per answer slot for Best Of card rendering.
    let imageURLs: [String?]

    init(question: Question, userAnswers: [String], imageURLs: [String?] = [nil, nil, nil]) {
        self.question = question
        self.userAnswers = userAnswers
        self.imageURLs = imageURLs
    }

    func resolvingUserAnswer(_ userAnswer: UserAnswer?) -> MostAnsweredItem {
        guard let userAnswer else { return self }
        return MostAnsweredItem(
            question: question,
            userAnswers: userAnswer.answers,
            imageURLs: userAnswer.imageURLs
        )
    }
}

// MARK: - View Model

@MainActor
final class MostAnsweredViewModel: ObservableObject {
    @Published private(set) var dailyItems: [MostAnsweredItem] = []
    @Published private(set) var allTimeItems: [MostAnsweredItem] = []
    @Published private(set) var isLoading = false
    @Published var error: String?

    private let loadItems: () async throws -> (daily: [MostAnsweredItem], allTime: [MostAnsweredItem])

    init(service: QuestionService = QuestionService()) {
        self.loadItems = {
            async let dailyFetch = service.fetchMostAnsweredQuestions(filter: .daily, limit: 20)
            async let allTimeFetch = service.fetchMostAnsweredQuestions(filter: .allTime, limit: 20)

            let (dailyQuestions, allTimeQuestions) = try await (dailyFetch, allTimeFetch)

            return (
                dailyQuestions.map { MostAnsweredItem(question: $0, userAnswers: []) },
                allTimeQuestions.map { MostAnsweredItem(question: $0, userAnswers: []) }
            )
        }
    }

    init(preloadedDailyItems: [MostAnsweredItem], preloadedAllTimeItems: [MostAnsweredItem]) {
        dailyItems = preloadedDailyItems
        allTimeItems = preloadedAllTimeItems
        loadItems = {
            (preloadedDailyItems, preloadedAllTimeItems)
        }
    }

    init(loadItems: @escaping () async throws -> (daily: [MostAnsweredItem], allTime: [MostAnsweredItem])) {
        self.loadItems = loadItems
    }

    func load() async {
        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            let loadedItems = try await loadItems()
            dailyItems = loadedItems.daily
            allTimeItems = loadedItems.allTime
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - Card Component

struct MostAnsweredQuestionCard: View {
    let item: MostAnsweredItem
    var headerStyle: ExpandedQuestionHeaderStyle?
    var sourceID: String = "mostAnswered"
    var onOpen: () -> Void

    @EnvironmentObject private var favoriteStore: FavoriteStore
    @Environment(\.toastCenter) private var toastCenter

    private var isFavorite: Bool {
        favoriteStore.state(of: item.question)
    }

    private var resolvedHeaderStyle: ExpandedQuestionHeaderStyle {
        headerStyle ?? .mostAnswered(respondentCount: item.question.totalRespondents)
    }

    private var questionAccessibilityLabel: String {
        String(
            format: String(localized: "bestof.questionAccessibility"),
            locale: AppLocalization.currentLocale,
            item.question.text
        )
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            primarySurface

            cardFooter
                .padding(.horizontal, QuestionCardLayoutMetrics.compactContentPadding)
                .padding(.bottom, QuestionCardLayoutMetrics.compactContentPadding)
        }
        .accessibilityElement(children: .contain)
    }

    private var primarySurface: some View {
        Button(action: onOpen) {
            cardContent
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .accessibilityIdentifier("question-card-\(sourceID)-\(item.question.id)")
        .accessibilityLabel(questionAccessibilityLabel)
        .accessibilityHint(String(localized: "bestof.questionHint"))
        .accessibilitySortPriority(1)
    }

    private var cardContent: some View {
        ZStack {
            cardBackground

            mainCardContent
                .padding(QuestionCardLayoutMetrics.compactContentPadding)
        }
        .frame(minHeight: 300)
        .contentShape(RoundedRectangle(cornerRadius: QuestionCardLayoutMetrics.compactCornerRadius))
        .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
    }

    private var mainCardContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            metaRow

            Spacer()
                .frame(height: 12)

            questionText

            Spacer()
                .frame(height: 18)

            answerComparison

            Spacer()
                .frame(height: 24)

            footerReservation
        }
    }

    // MARK: Meta row (category + respondent count)

    @ViewBuilder
    private var metaRow: some View {
        QuestionCardHeaderRow(
            question: item.question,
            headerStyle: resolvedHeaderStyle
        )
    }

    // MARK: Question text

    @ViewBuilder
    private var questionText: some View {
        Text(item.question.text)
            .font(.headline)
            .lineLimit(3)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, alignment: .center)
            .foregroundColor(.primary)
    }

    // MARK: Answer comparison

    private var answerComparison: some View {
        VStack(spacing: 0) {
            // Column headers
            HStack(spacing: 0) {
                Text(String(localized: "bestof.answer.mine"))
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Divider()
                    .frame(height: 14)
                    .padding(.horizontal, 8)

                Text(String(localized: "bestof.answer.others"))
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.bottom, 6)

            // Three answer rows
            ForEach(0..<3, id: \.self) { index in
                answerRow(for: index)
            }
        }
    }

    private func answerRow(for index: Int) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 0) {
                let myAnswer = index < item.userAnswers.count ? item.userAnswers[index] : ""
                let myImageURL = index < item.imageURLs.count ? item.imageURLs[index] : nil
                let hasImageAnswer = !(myImageURL?.isEmpty ?? true)
                let topAnswer = item.question.topAnswer(for: index)

                Group {
                    if !myAnswer.isEmpty {
                        Text(myAnswer)
                            .foregroundColor(.primary)
                            .accessibilityLabel(
                                String(
                                    format: String(localized: "bestof.answer.mineText"),
                                    locale: AppLocalization.currentLocale,
                                    myAnswer
                                )
                            )
                    } else if hasImageAnswer {
                        Image(systemName: "photo.badge.checkmark.fill")
                            .foregroundColor(.secondary)
                            .accessibilityLabel(String(localized: "bestof.answer.mineImage"))
                    } else {
                        Text("-")
                            .foregroundColor(.secondary)
                            .accessibilityLabel(String(localized: "bestof.answer.none"))
                    }
                }
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 6)

                Divider()
                    .padding(.horizontal, 8)

                Text(topAnswer ?? "-")
                    .font(.subheadline)
                    .foregroundColor(topAnswer == nil ? .secondary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
                    .accessibilityLabel(
                        topAnswer == nil
                            ? String(localized: "bestof.answer.noData")
                            : String(
                                format: String(localized: "bestof.answer.othersText"),
                                locale: AppLocalization.currentLocale,
                                topAnswer!
                            )
                    )
            }

            Divider()
        }
    }

    // MARK: Footer actions

    private var footerReservation: some View {
        HStack(alignment: .center, spacing: 12) {
            Color.clear
                .frame(maxWidth: .infinity)
                .accessibilityHidden(true)

            Color.clear
                .frame(width: actionCapsuleReservedWidth)
                .accessibilityHidden(true)
        }
        .frame(height: footerHeight)
    }

    private var cardFooter: some View {
        HStack(alignment: .center, spacing: 10) {
            QuestionCreatorAttributionView(question: item.question, style: .capsule)
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)

            actionCapsule
                .fixedSize()
        }
        .frame(height: footerHeight)
    }

    private var actionCapsule: some View {
        HStack(spacing: 2) {
            shareButton
            favoriteButton
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .compactQuestionActionCapsuleStyle()
    }

    private var shareButton: some View {
        ShareLink(item: item.question.shareURL) {
            Label(String(localized: "common.share"), systemImage: "square.and.arrow.up")
                .labelStyle(.iconOnly)
                .foregroundStyle(.gray)
                .frame(width: compactActionButtonSize, height: compactActionButtonSize)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(String(localized: "common.share"))
        .accessibilityIdentifier("question-card-share-\(sourceID)-\(item.question.id)")
        .buttonStyle(.plain)
    }

    private var favoriteButton: some View {
        Button {
            toggleFavorite()
        } label: {
            Label(
                String(localized: isFavorite ? "common.favorite.remove" : "common.favorite.add"),
                systemImage: isFavorite ? "star.fill" : "star"
            )
            .labelStyle(.iconOnly)
            .foregroundStyle(isFavorite ? .yellow : .gray)
            .frame(width: compactActionButtonSize, height: compactActionButtonSize)
            .contentShape(Rectangle())
            .animation(.easeInOut(duration: 0.2), value: isFavorite)
        }
        .accessibilityLabel(String(localized: isFavorite ? "common.favorite.remove" : "common.favorite.add"))
        .accessibilityIdentifier("question-card-favorite-\(sourceID)-\(item.question.id)")
        .buttonStyle(.plain)
    }

    private func toggleFavorite() {
        Task {
            await toastCenter.toggleFavorite(item.question, using: favoriteStore)
        }
    }

    private var footerHeight: CGFloat {
        42
    }

    private var compactActionButtonSize: CGFloat {
        30
    }

    private var actionCapsuleReservedWidth: CGFloat {
        (2 * compactActionButtonSize) + 2 + 14
    }

    @ViewBuilder
    private var cardBackground: some View {
        RoundedRectangle(
            cornerRadius: QuestionCardLayoutMetrics.compactCornerRadius,
            style: .continuous
        )
        .fill(Color.theme.secondaryBackground)
    }
}

// MARK: - Main View

struct MostAnsweredView: View {
    private enum TimeFilter: CaseIterable, Identifiable {
        case daily
        case allTime

        var id: Self { self }

        var title: String {
            switch self {
            case .daily:
                return String(localized: "bestof.filter.today")
            case .allTime:
                return String(localized: "bestof.filter.allTime")
            }
        }
    }

    /// Kept for the expanded edit card which needs QuestionModel to save answers.
    @EnvironmentObject private var questionModel: QuestionModel
    @EnvironmentObject private var badgeModel: BadgeModel
    @StateObject private var viewModel: MostAnsweredViewModel
    @State private var presentedQuestion: ExpandedQuestionState?
    @State private var selectedFilter: TimeFilter = .daily

    private let expansionSourceID = "mostAnswered"
    private let onShowHome: () -> Void

    @MainActor
    init(onShowHome: @escaping () -> Void = {}) {
        _viewModel = StateObject(wrappedValue: MostAnsweredViewModel())
        self.onShowHome = onShowHome
    }

    @MainActor
    init(
        viewModel: MostAnsweredViewModel,
        onShowHome: @escaping () -> Void = {}
    ) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self.onShowHome = onShowHome
    }

    private var currentItems: [MostAnsweredItem] {
        currentRankedItems.map { resolveUserData(for: $0) }
    }

    private var currentRankedItems: [MostAnsweredItem] {
        switch selectedFilter {
        case .daily:
            return viewModel.dailyItems
        case .allTime:
            return viewModel.allTimeItems
        }
    }

    var body: some View {
        let title = String(localized: "bestof.title")

        NavigationStack {
            contentView
            .background(Color.theme.background)
            .navigationChromeTitle(
                semanticTitle: title,
                visualTitle: Text(title)
            )
        }
        .fullScreenCover(
            item: $presentedQuestion
        ) { expandedState in
            QuestionDetailModalShell(
                expandedState: expandedState,
                model: questionModel,
                badgeModel: badgeModel
            )
        }
        .alert(
            String(localized: "common.error.title"),
            isPresented: Binding(
                get: { questionModel.error != nil },
                set: { if !$0 { questionModel.error = nil } }
            ),
            actions: {
                Button(String(localized: "common.ok")) { questionModel.error = nil }
            },
            message: {
                if let error = questionModel.error { Text(error) }
            }
        )
        .task {
            await viewModel.load()
        }
    }

    // MARK: Content

    @ViewBuilder
    private var contentView: some View {
        // Resolved once and threaded down: `currentItems` rebuilds every item to fold in the user's
        // own answers, and it was read for the empty check and again for the `ForEach`.
        let items = currentItems

        VStack(spacing: 12) {
            Picker(String(localized: "bestof.filter.label"), selection: $selectedFilter) {
                ForEach(TimeFilter.allCases) { filter in
                    Text(filter.title).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.top, 8)

            if viewModel.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityLabel(String(localized: "bestof.loading"))
            } else if let errorMessage = viewModel.error {
                errorView(message: errorMessage)
            } else if items.isEmpty {
                emptyStateView
            } else {
                ScrollView {
                    LazyVStack(spacing: 16) {
                        ForEach(items) { item in
                            MostAnsweredQuestionCard(
                                item: item,
                                headerStyle: .mostAnswered(
                                    respondentCount: item.question.totalRespondents
                                ),
                                sourceID: expansionSourceID,
                                onOpen: {
                                    openExpanded(for: item)
                                }
                            )
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal)
                        }
                    }
                    .padding(.vertical)
                }
                .refreshable {
                    await viewModel.load()
                }
            }
        }
    }

    // MARK: Empty State

    private var emptyStateView: some View {
        VStack(spacing: 6) {
            Image(systemName: "star.fill")
                .font(.system(size: 48, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.bottom, 10)

            Text(String(localized: "bestof.emptyTitle"))
                .font(.title3)
                .fontWeight(.bold)
                .foregroundStyle(.primary)

            Text(emptyDescription)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(2)

            Button(String(localized: "bestof.emptyAction")) {
                onShowHome()
            }
            .font(.body)
            .padding(.top, 22)
            .accessibilityLabel(String(localized: "bestof.emptyActionAccessibility"))
        }
        .padding(.horizontal, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyDescription: String {
        switch selectedFilter {
        case .daily:
            return String(localized: "bestof.emptyDescription.today")
        case .allTime:
            return String(localized: "bestof.emptyDescription.allTime")
        }
    }

    private func errorView(message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundColor(.orange)
            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Button(String(localized: "common.retry")) {
                Task { await viewModel.load() }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Helpers

    private func resolveUserData(for item: MostAnsweredItem) -> MostAnsweredItem {
        item.resolvingUserAnswer(questionModel.currentUserAnswers[item.id])
    }

    private func openExpanded(for item: MostAnsweredItem) {
        // Prefer the live question from the global listener (most up-to-date data).
        // Fall back to the item's snapshot if it's not yet in the listener cache.
        let baseQuestion = questionModel.questions.first(where: { $0.id == item.question.id })
            ?? item.question

        // Pre-populate the expanded edit view with THIS user's own answers
        // rather than whoever last wrote the global answers field.
        let answersToShow: [String]
        if let userAnswer = questionModel.currentUserAnswers[item.id] {
            var padded = userAnswer.answers
            while padded.count < 3 { padded.append("") }
            answersToShow = Array(padded.prefix(3))
        } else if !item.userAnswers.isEmpty {
            var padded = item.userAnswers
            while padded.count < 3 { padded.append("") }
            answersToShow = Array(padded.prefix(3))
        } else {
            var padded = baseQuestion.answers
            while padded.count < 3 { padded.append("") }
            answersToShow = Array(padded.prefix(3))
        }

        let questionWithUserAnswers = Question(
            id: baseQuestion.id,
            text: baseQuestion.text,
            category: baseQuestion.category,
            contentId: baseQuestion.contentId,
            localizedTexts: baseQuestion.localizedTexts,
            languageCode: baseQuestion.languageCode,
            source: baseQuestion.source,
            answers: answersToShow,
            isFavorite: baseQuestion.isFavorite,
            createdAt: baseQuestion.createdAt,
            createdBy: baseQuestion.createdBy,
            creatorUsername: baseQuestion.creatorUsername,
            isAnnounced: baseQuestion.isAnnounced,
            moderationStatus: baseQuestion.moderationStatus,
            moderatedAt: baseQuestion.moderatedAt,
            moderatedBy: baseQuestion.moderatedBy,
            rejectionReason: baseQuestion.rejectionReason,
            featuredPlacement: baseQuestion.featuredPlacement,
            lastAnsweredAt: baseQuestion.lastAnsweredAt,
            announcedAt: baseQuestion.announcedAt,
            announcedInReleaseId: baseQuestion.announcedInReleaseId,
            totalRespondents: baseQuestion.totalRespondents,
            todayRespondents: baseQuestion.todayRespondents,
            todayDate: baseQuestion.todayDate,
            answerStats: baseQuestion.answerStats
        )

        presentedQuestion = ExpandedQuestionState(
            question: questionWithUserAnswers,
            headerStyle: .mostAnswered(respondentCount: item.question.totalRespondents)
        )
    }
}

#Preview {
    MostAnsweredView()
        .environmentObject(AuthModel())
        .environmentObject(FavoriteStore.previews)
        .environmentObject(GuestFavoriteModel())
        .environmentObject(QuestionModel())
        .environmentObject(BadgeModel())
}
