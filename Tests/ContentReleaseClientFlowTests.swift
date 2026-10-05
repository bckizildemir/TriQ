import Foundation
import Testing
@testable import TTB

@MainActor
struct ContentReleaseClientFlowTests {
    // Nonisolated on purpose: the notification delegate parses the payload off the main actor.
    @Test
    nonisolated func extractsReleaseIDFromNotificationPayload() {
        #expect(NotificationService.releaseID(from: ["releaseId": "release-123"]) == "release-123")
        #expect(NotificationService.releaseID(from: ["releaseId": 42]) == nil)
        #expect(NotificationService.releaseID(from: [:]) == nil)
    }

    @Test
    func loadsPublishedReleaseContent() async {
        let category = sampleCategory()
        let question = sampleQuestion(categoryID: category.id)
        let release = sampleRelease(categoryIDs: [category.id], questionIDs: [question.id])
        let viewModel = ContentReleaseDetailViewModel(
            releaseID: release.id,
            releaseService: MockContentReleaseReader(
                release: release,
                questions: [question]
            ),
            categoryService: MockCategoryReader(categories: [category])
        )

        await viewModel.load()

        #expect(viewModel.isLoading == false)
        #expect(viewModel.errorMessage == nil)
        #expect(viewModel.release == release)
        #expect(viewModel.categories == [category])
        #expect(viewModel.questions.map(\.id) == [question.id])
        #expect(viewModel.questions.first?.text == question.text)
    }

    @Test
    func clearsLoadedContentWhenRelatedFetchFails() async {
        let category = sampleCategory()
        let question = sampleQuestion(categoryID: category.id)
        let release = sampleRelease(categoryIDs: [category.id], questionIDs: [question.id])
        let failingError = URLError(.cannotLoadFromNetwork)
        let viewModel = ContentReleaseDetailViewModel(
            releaseID: release.id,
            releaseService: MockContentReleaseReader(
                release: release,
                questionsError: failingError
            ),
            categoryService: MockCategoryReader(categories: [category])
        )

        await viewModel.load()

        #expect(viewModel.isLoading == false)
        #expect(viewModel.release == nil)
        #expect(viewModel.categories.isEmpty)
        #expect(viewModel.questions.isEmpty)
        #expect(viewModel.errorMessage == failingError.localizedDescription)
    }

    private func sampleRelease(categoryIDs: [String], questionIDs: [String]) -> ContentRelease {
        ContentRelease(
            id: "release-123",
            localizedTitle: ["en": "Fresh prompts", "tr": "Yeni sorular"],
            localizedBody: ["en": "Open the app", "tr": "Uygulamayi ac"],
            categoryIds: categoryIDs,
            questionIds: questionIDs,
            status: .published,
            publishedAt: Date(timeIntervalSince1970: 200),
            createdAt: Date(timeIntervalSince1970: 100)
        )
    }

    private func sampleCategory() -> TTB.Category {
        TTB.Category(
            id: "Mindset",
            localizedNames: ["en": "Mindset", "tr": "Zihin"],
            iconSystemName: "brain.head.profile",
            sortOrder: 1,
            isActive: true,
            isAnnounced: true,
            createdAt: Date(timeIntervalSince1970: 50)
        )
    }

    private func sampleQuestion(categoryID: String) -> Question {
        Question(
            id: "question-1",
            text: "What grounded you today?",
            category: categoryID,
            source: .seeded,
            createdAt: Date(timeIntervalSince1970: 60),
            isAnnounced: true
        )
    }
}

private struct MockContentReleaseReader: ContentReleaseReading {
    var release: ContentRelease?
    var questions: [Question] = []
    var releaseError: Error?
    var questionsError: Error?

    func fetchRelease(id: String) async throws -> ContentRelease? {
        if let releaseError {
            throw releaseError
        }

        return release
    }

    func fetchQuestions(ids: [String]) async throws -> [Question] {
        if let questionsError {
            throw questionsError
        }

        return questions
    }
}

private struct MockCategoryReader: CategoryReading {
    var categories: [TTB.Category] = []
    var error: Error?

    func fetchCategories(ids: [String]) async throws -> [TTB.Category] {
        if let error {
            throw error
        }

        return categories
    }
}
