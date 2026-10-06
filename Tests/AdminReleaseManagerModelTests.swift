import FirebaseFirestore
import Foundation
import Testing
@testable import TTB

@MainActor
struct AdminReleaseManagerModelTests {
    @Test
    func testNotificationRequiresEnglishTitleAndBody() async {
        let model = AdminReleaseManagerModel(releaseService: MockContentReleaseService())

        #expect(model.canSendTestNotification == false)

        model.titleEN = "Fresh prompts"
        #expect(model.canSendTestNotification == false)

        model.bodyEN = "Open the app"
        #expect(model.canSendTestNotification == true)
    }

    @Test
    func sendTestNotificationShowsSuccessMessage() async {
        let service = MockContentReleaseService(
            testNotificationResult: ContentReleaseNotificationSendResult(
                attemptedCount: 1,
                successCount: 1,
                failureCount: 0,
                prunedCount: 0
            )
        )
        let model = AdminReleaseManagerModel(releaseService: service)
        model.titleEN = "Fresh prompts"
        model.bodyEN = "Open the app"

        await model.sendTestNotification()

        #expect(model.errorMessage == nil)
        #expect(model.testNotificationMessage?.contains("1") == true)
        #expect(await service.sentLocalizedTitle == ["en": "Fresh prompts"])
        #expect(await service.sentLocalizedBody == ["en": "Open the app"])
    }

    @Test
    func sendTestNotificationShowsNoEligibleDeviceMessage() async {
        let model = AdminReleaseManagerModel(
            releaseService: MockContentReleaseService(testNotificationResult: .empty)
        )
        model.titleEN = "Fresh prompts"
        model.bodyEN = "Open the app"

        await model.sendTestNotification()

        #expect(model.errorMessage == nil)
        #expect(model.testNotificationMessage?.contains("No eligible device") == true)
    }

    @Test
    func sendTestNotificationMapsServiceFailureToErrorMessage() async {
        let model = AdminReleaseManagerModel(
            releaseService: MockContentReleaseService(testNotificationError: ContentReleaseServiceError.adminRequired)
        )
        model.titleEN = "Fresh prompts"
        model.bodyEN = "Open the app"

        await model.sendTestNotification()

        #expect(model.testNotificationMessage == nil)
        #expect(model.errorMessage == ContentReleaseServiceError.adminRequired.errorDescription)
    }
}

private actor MockContentReleaseService: ContentReleaseServicing {
    var sentLocalizedTitle: [String: String]?
    var sentLocalizedBody: [String: String]?

    private let testNotificationResult: ContentReleaseNotificationSendResult
    private let testNotificationError: Error?

    init(
        testNotificationResult: ContentReleaseNotificationSendResult = .empty,
        testNotificationError: Error? = nil
    ) {
        self.testNotificationResult = testNotificationResult
        self.testNotificationError = testNotificationError
    }

    nonisolated func listenToReleases(
        completion: @escaping (Result<[ContentRelease], Error>) -> Void
    ) -> any ListenerRegistration {
        MockContentReleaseListener()
    }

    func publishPendingRelease(
        localizedTitle: [String: String],
        localizedBody: [String: String]
    ) async throws -> (releaseID: String?, didPublish: Bool) {
        (releaseID: nil, didPublish: false)
    }

    func sendTestNotification(
        localizedTitle: [String: String],
        localizedBody: [String: String]
    ) async throws -> ContentReleaseNotificationSendResult {
        if let testNotificationError {
            throw testNotificationError
        }

        sentLocalizedTitle = localizedTitle
        sentLocalizedBody = localizedBody
        return testNotificationResult
    }

    func fetchPendingCategories() async throws -> [TTB.Category] {
        []
    }

    func fetchEligibleQuestions() async throws -> [Question] {
        []
    }

    nonisolated func suggestedCopy(
        categoryIDs: [String],
        questions: [Question],
        categories: [TTB.Category]
    ) -> (title: [String: String], body: [String: String]) {
        (title: [:], body: [:])
    }

    func fetchRelease(id: String) async throws -> ContentRelease? {
        nil
    }

    func fetchQuestions(ids: [String]) async throws -> [Question] {
        []
    }
}

private final class MockContentReleaseListener: NSObject, ListenerRegistration {
    func remove() {}
}
