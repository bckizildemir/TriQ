import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var deepLinkRouter: AppDeepLinkRouter
    @EnvironmentObject private var authModel: AuthModel
    @EnvironmentObject private var profileModel: ProfileModel
    @EnvironmentObject private var categoryModel: CategoryModel
    @EnvironmentObject private var model: QuestionModel
    @EnvironmentObject private var badgeModel: BadgeModel
    private let isPreviewFixture: Bool
    private let profileViewBuilder: (() -> ProfileView)?
    @State private var presentedQuestion: ExpandedQuestionState?
    @State private var showingProfileSheet = false
    @State private var navigationPath: [HomeRoute] = []

    private enum HomeRoute: Hashable {
        case acceptedQuestionListShareDetail(String)
    }

    @MainActor
    init(
        isPreviewFixture: Bool = false,
        profileViewBuilder: (() -> ProfileView)? = nil
    ) {
        self.isPreviewFixture = isPreviewFixture
        self.profileViewBuilder = profileViewBuilder
    }

    private var homeCategories: [Category] {
        categoryModel.activeCategories.filter { $0.id != "Daily" }
    }

    var body: some View {
        GeometryReader { geometry in
            let maximumCardHeight = homeCardMaximumHeight(in: geometry)

            NavigationStack(path: $navigationPath) {
                ScrollView {
                    // Lazy, not eager: each `CategorySection` wraps a page-style `TabView` that
                    // builds every card in its category up front, and there are ~23 sections. A
                    // plain `VStack` materialized all of them on first render and rebuilt them on
                    // every invalidation.
                    LazyVStack(alignment: .leading, spacing: 24) {
                        if model.isLoading {
                            ProgressView()
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else {
                            if !homeCategories.isEmpty {
                                CategoryChipsRow(categories: homeCategories) { category in
                                    CategoryQuestionsView(
                                        category: category.id,
                                        model: model,
                                        badgeModel: badgeModel
                                    )
                                }
                            }

                            if !model.todaysQuestions.isEmpty {
                                CategorySection(
                                    title: String(localized: "main.home.todayQuestions"),
                                    icon: "calendar",
                                    questions: model.todaysQuestions,
                                    model: model,
                                    badgeModel: badgeModel,
                                    categoryColor: categoryModel.color(for: "Daily"),
                                    sourceID: "home.today",
                                    maximumCardHeight: maximumCardHeight,
                                    onQuestionTap: { question in
                                        presentedQuestion = ExpandedQuestionState(
                                            question: question,
                                            headerStyle: .plain
                                        )
                                    }
                                )
                            }

                            ForEach(homeCategories) { category in
                                CategorySection(
                                    title: category.displayName,
                                    icon: category.iconSystemName,
                                    questions: model.questions(for: category.id),
                                    model: model,
                                    badgeModel: badgeModel,
                                    categoryKey: category.id,
                                    categoryColor: category.colorToken.color,
                                    sourceID: "home.category.\(category.id)",
                                    maximumCardHeight: maximumCardHeight,
                                    onQuestionTap: { question in
                                        presentedQuestion = ExpandedQuestionState(
                                            question: question,
                                            headerStyle: .plain
                                        )
                                    }
                                )
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                    .padding(.bottom, 20)
                }
                
                // background effect that blurs content as it passes under toolbars
                // .scrollEdgeEffectStyle(.hard, for: .top)

                .background(Color.theme.background)
                .navigationChromeTitle(
                    semanticTitle: timeBasedGreeting,
                    visualTitle: Text(timeBasedGreeting),
                    visualSubtitle: Text(formattedNavigationDate),
                    titleFont: .system(size: 20, weight: .semibold),
                    subtitleFont: .system(size: 13, weight: .semibold)
                )
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(action: {
                            guard !isPreviewFixture else { return }
                            showingProfileSheet = true
                        }) {
                            profileToolbarButtonImage
                        }
                        .accessibilityLabel(Text(String(localized: "main.home.profile")))
                        .accessibilityHint(Text(String(localized: "main.home.profileHint")))
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    Color.clear.frame(height: 0)
                }
                .fullScreenCover(isPresented: $showingProfileSheet) {
                    if let profileViewBuilder {
                        profileViewBuilder()
                    } else {
                        ProfileView()
                    }
                }
                .navigationDestination(for: HomeRoute.self) { route in
                    switch route {
                    case .acceptedQuestionListShareDetail(let shareId):
                        AcceptedQuestionListShareDetailView(acceptedShareID: shareId)
                    }
                }
            }
        }
        .onChange(of: deepLinkRouter.acceptedQuestionListShareDetail) { _, request in
            guard let request else { return }
            navigationPath = [.acceptedQuestionListShareDetail(request.shareId)]
            deepLinkRouter.consumeAcceptedQuestionListShareDetail(request)
        }
        .fullScreenCover(item: $presentedQuestion) { expandedState in
            QuestionDetailModalShell(
                expandedState: expandedState,
                model: model,
                badgeModel: badgeModel,
                onClose: {
                    presentedQuestion = nil
                }
            )
        }
        .alert(
            String(localized: "common.error.title"),
            isPresented: Binding(
                get: { model.error != nil },
                set: { if !$0 { model.error = nil } }
            ),
            actions: {
                Button(String(localized: "common.ok")) { model.error = nil }
            },
            message: {
                if let error = model.error { Text(error) }
            }
        )
    }

    private var timeBasedGreeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 6..<11: return String(localized: "home.greeting.morning")
        case 11..<18: return String(localized: "home.greeting.day")
        case 18..<22: return String(localized: "home.greeting.evening")
        default: return String(localized: "home.greeting.night")
        }
    }

    private var formattedNavigationDate: String {
        Date.now.formatted(
            .dateTime
                .weekday(.abbreviated)
                .day()
                .month(.abbreviated)
                .locale(AppLocalization.currentLocale)
        )
    }

    @ViewBuilder
    private var profileToolbarButtonImage: some View {
        if authModel.isAuthenticated,
           !authModel.isAnonymous,
           let profileImage = profileModel.profileImage {
            Image(uiImage: profileImage)
                .resizable()
                .scaledToFill()
                .frame(width: 28, height: 28)
                .clipShape(Circle())
                .contentShape(Circle())
        } else {
            Image(systemName: "person.circle.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.primary)
                .contentShape(Rectangle())
        }
    }

    private func homeCardMaximumHeight(in geometry: GeometryProxy) -> CGFloat {
        let safeAreaHeight = geometry.size.height - geometry.safeAreaInsets.top - geometry.safeAreaInsets.bottom
        return max(460, min(safeAreaHeight - 40, 620))
    }
}

private extension HomeView {
    static let previewCategories = Category.defaultCategories

    static let previewQuestions: [Question] = {
        let questionsByCategory = Dictionary(grouping: Question.sampleQuestions, by: \.category)

        return previewCategories.compactMap { category in
            guard var question = questionsByCategory[category.id]?.first else { return nil }

            if category.id == "Daily" {
                question.isFavorite = true
            }

            return question
        }
    }()

    static let previewUserAnswers: [String: UserAnswer] = {
        guard previewQuestions.count >= 3 else { return [:] }

        return [
            previewQuestions[0].id: UserAnswer(
                questionId: previewQuestions[0].id,
                userId: "preview-user",
                answers: [
                    "Sessiz bir sabah kahvesi",
                    "İlerleyen işler",
                    "Akşam yürüyüşü"
                ],
                answeredAt: .now
            ),
            previewQuestions[1].id: UserAnswer(
                questionId: previewQuestions[1].id,
                userId: "preview-user",
                answers: [
                    "Odaklı çalışma",
                    "Kısa bir mola",
                    ""
                ],
                answeredAt: .now
            ),
            previewQuestions[2].id: UserAnswer(
                questionId: previewQuestions[2].id,
                userId: "preview-user",
                answers: [
                    "Daha sık aramak",
                    "Birlikte plan yapmak",
                    "Daha dikkatli dinlemek"
                ],
                answeredAt: .now
            )
        ]
    }()
}

struct CategorySection: View {
    let title: String
    let icon: String
    let questions: [Question]
    let model: QuestionModel
    let badgeModel: BadgeModel?
    var categoryKey: String?
    var categoryColor: Color = .accentColor
    let sourceID: String
    let maximumCardHeight: CGFloat
    var onQuestionTap: ((Question) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(title, systemImage: icon)
                    .font(.title2.bold())
                    .foregroundStyle(categoryColor)
                Spacer()
                if let categoryKey {
                    NavigationLink(destination: CategoryQuestionsView(category: categoryKey, model: model, badgeModel: badgeModel)) {
                        Text(String(localized: "main.home.viewAll"))
                            .foregroundColor(categoryColor)
                            .font(.footnote)
                    }
                }
            }

            PagedCardView(
                questions: questions,
                model: model,
                sourceID: sourceID,
                badgeModel: badgeModel,
                onQuestionTap: onQuestionTap,
                showImages: true,
                showsShareButton: true,
                maximumCardHeight: maximumCardHeight,
                cardPresentationStyle: .pagedFeed,
                categoryColor: categoryColor
            )
        }
    }
}

#Preview {
    HomeView(isPreviewFixture: true)
    .environmentObject(
        QuestionModel(
            localQuestions: HomeView.previewQuestions,
            localUserAnswers: HomeView.previewUserAnswers
        )
    )
    .environmentObject(AuthModel())
    .environmentObject(ProfileModel(userId: "preview", startsAuthListener: false, loadsRemoteData: false))
    .environmentObject(AppDeepLinkRouter())
    .environmentObject(FavoriteStore.previews)
    .environmentObject(GuestFavoriteModel())
    .environmentObject(CategoryModel(localCategories: HomeView.previewCategories))
    .environmentObject(BadgeModel())
}
