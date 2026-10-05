import SwiftUI

@MainActor
final class ContentReleaseDetailViewModel: ObservableObject {
    @Published private(set) var release: ContentRelease?
    @Published private(set) var categories: [Category] = []
    @Published private(set) var questions: [Question] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let releaseID: String
    private let releaseService: any ContentReleaseReading
    private let categoryService: any CategoryReading

    init(
        releaseID: String,
        releaseService: any ContentReleaseReading = ContentReleaseService(),
        categoryService: any CategoryReading = CategoryService()
    ) {
        self.releaseID = releaseID
        self.releaseService = releaseService
        self.categoryService = categoryService
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }

        do {
            guard let release = try await releaseService.fetchRelease(id: releaseID) else {
                clearLoadedContent()
                errorMessage = "This release could not be found."
                return
            }

            async let fetchedCategories = categoryService.fetchCategories(ids: release.categoryIds)
            async let fetchedQuestions = releaseService.fetchQuestions(ids: release.questionIds)

            let categories = try await fetchedCategories
            let questions = try await fetchedQuestions

            self.release = release
            self.categories = categories
            self.questions = questions
            self.errorMessage = nil
        } catch {
            clearLoadedContent()
            self.errorMessage = error.localizedDescription
        }
    }

    private func clearLoadedContent() {
        release = nil
        categories = []
        questions = []
    }
}

struct ContentReleaseDetailView: View {
    let releaseID: String

    @EnvironmentObject private var questionModel: QuestionModel
    @StateObject private var viewModel: ContentReleaseDetailViewModel
    @State private var presentedQuestion: ExpandedQuestionState?

    init(releaseID: String) {
        self.releaseID = releaseID
        _viewModel = StateObject(wrappedValue: ContentReleaseDetailViewModel(releaseID: releaseID))
    }

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading {
                    ProgressView()
                } else if let release = viewModel.release {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            header(release)

                            if !viewModel.categories.isEmpty {
                                categoriesSection
                            }

                            if !viewModel.questions.isEmpty {
                                questionsSection
                            }
                        }
                        .padding(20)
                    }
                    .background(Color.theme.background)
                } else {
                    ContentUnavailableView(
                        "Release Unavailable",
                        systemImage: "bell.slash",
                        description: Text(viewModel.errorMessage ?? "The requested release is no longer available.")
                    )
                }
            }
            .navigationTitle("What’s New")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                await viewModel.load()
            }
        }
        .fullScreenCover(item: $presentedQuestion) { expandedState in
            QuestionDetailModalShell(
                expandedState: expandedState,
                model: questionModel,
                badgeModel: nil,
                onClose: {
                    presentedQuestion = nil
                }
            )
        }
    }

    private var categoriesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Categories")
                .font(.headline)

            FlowLayout(spacing: 10) {
                ForEach(viewModel.categories) { category in
                    categoryChip(category)
                }
            }
        }
    }

    private var questionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Questions")
                .font(.headline)

            ForEach(viewModel.questions) { question in
                Button {
                    presentedQuestion = ExpandedQuestionState(
                        question: question,
                        headerStyle: .plain
                    )
                } label: {
                    questionRow(question)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func categoryChip(_ category: Category) -> some View {
        Label(category.displayName, systemImage: category.iconSystemName)
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(Color.accentColor.opacity(0.12))
            )
    }

    private func questionRow(_ question: Question) -> some View {
        let category = viewModel.categories.first(where: { $0.id == question.category })
        let categoryTitle = category?.displayName ?? Category.fallbackTitle(for: question.category)
        let categoryIcon = category?.iconSystemName ?? Category.fallbackIcon(for: question.category)

        return VStack(alignment: .leading, spacing: 8) {
            Text(question.text)
                .font(.body.weight(.medium))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)

            Label(categoryTitle, systemImage: categoryIcon)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.theme.secondaryBackground)
        )
    }

    private func header(_ release: ContentRelease) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(release.title)
                .font(.largeTitle.bold())

            Text(release.body)
                .font(.body)
                .foregroundStyle(.secondary)

            if let publishedAt = release.publishedAt {
                Label(
                    publishedAt.formatted(
                        Date.FormatStyle(date: .abbreviated, time: .shortened)
                            .locale(AppLocalization.currentLocale)
                    ),
                    systemImage: "calendar.badge.clock"
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }
    }
}

private struct FlowLayout<Content: View>: View {
    let spacing: CGFloat
    @ViewBuilder let content: Content

    init(spacing: CGFloat = 8, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
