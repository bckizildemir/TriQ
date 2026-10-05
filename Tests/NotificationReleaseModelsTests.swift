import FirebaseFirestore
import XCTest
@testable import TTB

final class NotificationReleaseModelsTests: XCTestCase {
    func testCategoryFirestoreRoundTrip() {
        let category = Category(
            id: "Mindset",
            localizedNames: ["en": "Mindset", "tr": "Zihin"],
            iconSystemName: "brain.head.profile",
            colorToken: .systemMint,
            sortOrder: 8,
            isActive: true,
            isAnnounced: true,
            createdAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 200),
            createdBy: "admin-1",
            announcedAt: Date(timeIntervalSince1970: 300),
            announcedInReleaseId: "release-1"
        )

        let parsed = Category.fromFirestore(category.toFirestore(), id: category.id)

        XCTAssertEqual(parsed.id, "Mindset")
        XCTAssertEqual(parsed.localizedNames["en"], "Mindset")
        XCTAssertEqual(parsed.iconSystemName, "brain.head.profile")
        XCTAssertEqual(parsed.colorToken, .systemMint)
        XCTAssertEqual(parsed.sortOrder, 8)
        XCTAssertEqual(parsed.createdBy, "admin-1")
        XCTAssertTrue(parsed.isAnnounced)
        XCTAssertEqual(parsed.announcedInReleaseId, "release-1")
    }

    func testLegacyCategoryDefaultsIsAnnouncedToTrue() {
        let data: [String: Any] = [
            "localizedNames": ["en": "Mindset", "tr": "Zihin"],
            "iconSystemName": "brain.head.profile",
            "sortOrder": 8,
            "createdAt": Timestamp(date: Date(timeIntervalSince1970: 100)),
        ]

        let parsed = Category.fromFirestore(data, id: "Mindset")

        XCTAssertTrue(parsed.isAnnounced)
    }

    func testLegacyCategoryDefaultsColorTokenFromCategoryID() {
        let data: [String: Any] = [
            "localizedNames": ["en": "Career", "tr": "Kariyer"],
            "iconSystemName": "briefcase.fill",
            "sortOrder": 3,
            "createdAt": Timestamp(date: Date(timeIntervalSince1970: 100)),
        ]

        let parsed = Category.fromFirestore(data, id: "Career")

        XCTAssertEqual(parsed.colorToken, .systemIndigo)
    }

    func testInvalidCategoryColorTokenFallsBackSafely() {
        let data: [String: Any] = [
            "localizedNames": ["en": "Unknown"],
            "iconSystemName": "square.grid.2x2",
            "colorToken": "not-a-system-color",
            "sortOrder": 99,
            "createdAt": Timestamp(date: Date(timeIntervalSince1970: 100)),
        ]

        let parsed = Category.fromFirestore(data, id: "Unknown")

        XCTAssertEqual(parsed.colorToken, .systemBlue)
    }

    func testContentReleaseFirestoreRoundTrip() {
        let release = ContentRelease(
            id: "release-1",
            localizedTitle: ["en": "Fresh prompts", "tr": "Yeni sorular"],
            localizedBody: ["en": "Open the app", "tr": "Uygulamayi ac"],
            categoryIds: ["Daily", "Goals"],
            questionIds: ["q1", "q2"],
            status: .scheduled,
            scheduledAt: Date(timeIntervalSince1970: 1000),
            publishedAt: nil,
            createdAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 200),
            createdBy: "admin-1"
        )

        let parsed = ContentRelease.fromFirestore(release.toFirestore(), id: release.id)

        XCTAssertEqual(parsed.id, "release-1")
        XCTAssertEqual(parsed.status, .scheduled)
        XCTAssertEqual(parsed.categoryIds, ["Daily", "Goals"])
        XCTAssertEqual(parsed.questionIds, ["q1", "q2"])
        XCTAssertEqual(parsed.localizedTitle["tr"], "Yeni sorular")
        XCTAssertEqual(parsed.createdBy, "admin-1")
    }

    func testLegacyReleaseWithoutStatusDefaultsToPublishedHistory() {
        let data: [String: Any] = [
            "localizedTitle": ["en": "Fresh prompts"],
            "localizedBody": ["en": "Open the app"],
            "categoryIds": ["Daily"],
            "questionIds": ["question-1"],
            "createdAt": Timestamp(date: Date(timeIntervalSince1970: 100)),
        ]

        let parsed = ContentRelease.fromFirestore(data, id: "release-legacy")

        XCTAssertEqual(parsed.status, .published)
        XCTAssertTrue(parsed.isPublished)
    }

    func testNotificationDeviceFirestoreRoundTrip() {
        let device = NotificationDevice(
            id: "device-1",
            fcmToken: "token-123",
            localeCode: "tr",
            contentUpdatesEnabled: true,
            authorizationStatus: .authorized,
            isPushEligible: true,
            appVersion: "1.0"
        )

        let parsed = NotificationDevice.fromFirestore(device.toFirestore(), id: device.id)

        XCTAssertEqual(parsed.id, "device-1")
        XCTAssertEqual(parsed.fcmToken, "token-123")
        XCTAssertEqual(parsed.localeCode, "tr")
        XCTAssertEqual(parsed.authorizationStatus, .authorized)
        XCTAssertTrue(parsed.isPushEligible)
    }

    func testLegacyQuestionDecodesWithoutDynamicCategoryFields() {
        let data: [String: Any] = [
            "text": "What grounded you today?",
            "category": "Daily",
            "createdAt": Timestamp(date: Date(timeIntervalSince1970: 50)),
            "source": QuestionSource.seeded.rawValue
        ]

        let question = Question.fromFirestore(data, id: "question-1")
        let expectedLegacyQuestion = Question(
            id: "expected-legacy",
            text: "What grounded you today?",
            category: "Daily"
        )

        XCTAssertNotNil(question)
        XCTAssertEqual(question?.id, "question-1")
        XCTAssertEqual(question?.category, "Daily")
        XCTAssertEqual(question?.contentId, expectedLegacyQuestion.contentId)
        XCTAssertEqual(question?.isAnnounced, true)
        XCTAssertNil(question?.announcedInReleaseId)
    }
}
