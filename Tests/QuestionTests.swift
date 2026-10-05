import XCTest
import FirebaseFirestore
@testable import TTB

final class QuestionTests: XCTestCase {

    func testFromFirestoreDefaultsSourceToSeeded() {
        let data: [String: Any] = [
            "text": "En sevdiğin 3 renk ne?",
            "category": "Daily",
            "createdAt": Timestamp(date: Date())
        ]

        let question = Question.fromFirestore(data, id: "question-1")

        XCTAssertEqual(question?.source, .seeded)
        XCTAssertEqual(question?.isAnnounced, true)
        XCTAssertEqual(question?.moderationStatus, .approved)
    }

    func testFromFirestoreRejectsMalformedTrustAndVisibilityFields() {
        let validData: [String: Any] = [
            "text": "Which 3 moments mattered today?",
            "category": "Daily",
            "createdAt": Timestamp(date: Date()),
        ]
        let malformedFields: [(key: String, value: Any)] = [
            ("source", "unknown"),
            ("source", 1),
            ("isAnnounced", "false"),
            ("moderationStatus", "published"),
            ("moderationStatus", 1),
        ]

        for malformedField in malformedFields {
            var data = validData
            data[malformedField.key] = malformedField.value

            XCTAssertNil(
                Question.fromFirestore(data, id: "malformed-\(malformedField.key)"),
                "Expected malformed \(malformedField.key) to be rejected"
            )
        }
    }

    func testFromFirestoreRejectsBlankRequiredTextAndCategory() {
        let createdAt = Timestamp(date: Date())

        XCTAssertNil(Question.fromFirestore([
            "text": " \n ",
            "category": "Daily",
            "createdAt": createdAt,
        ], id: "blank-text"))
        XCTAssertNil(Question.fromFirestore([
            "text": "Which 3 moments mattered today?",
            "category": "\t",
            "createdAt": createdAt,
        ], id: "blank-category"))
    }

    func testFromFirestoreReplacesBlankContentIDWithStableLegacyIdentity() {
        let data: [String: Any] = [
            "text": "Which 3 moments mattered today?",
            "category": "Daily",
            "contentId": " \n ",
            "createdAt": Timestamp(date: Date()),
        ]

        let first = Question.fromFirestore(data, id: "document-a")
        let second = Question.fromFirestore(data, id: "document-b")

        XCTAssertFalse(first?.contentId.isEmpty ?? true)
        XCTAssertEqual(first?.contentId, second?.contentId)
    }

    func testFromFirestoreReadsUserCreatedSource() {
        let data: [String: Any] = [
            "text": "Son zamanlarda seni güldüren 3 şey neydi?",
            "category": "Personal",
            "source": "userCreated",
            "createdAt": Timestamp(date: Date()),
            "createdBy": "user-123",
            "creatorUsername": "berke"
        ]

        let question = Question.fromFirestore(data, id: "question-2")

        XCTAssertEqual(question?.source, .userCreated)
        XCTAssertEqual(question?.createdBy, "user-123")
        XCTAssertEqual(question?.creatorUsername, "berke")
        XCTAssertEqual(question?.creatorAttributionUsername, "berke")
        XCTAssertEqual(question?.moderationStatus, .approved)
    }

    func testToFirestoreIncludesSourceAndModerationFields() {
        let question = Question(
            id: "question-3",
            text: "Top 3 comfort meal'in ne?",
            category: "Daily",
            source: .userCreated,
            createdAt: Date(timeIntervalSince1970: 1234),
            createdBy: "user-42",
            creatorUsername: "ceren",
            isAnnounced: false,
            moderationStatus: .pending,
            featuredPlacement: .none
        )

        let data = question.toFirestore()

        XCTAssertEqual(data["source"] as? String, QuestionSource.userCreated.rawValue)
        XCTAssertEqual(data["createdBy"] as? String, "user-42")
        XCTAssertEqual(data["creatorUsername"] as? String, "ceren")
        XCTAssertEqual(data["isAnnounced"] as? Bool, false)
        XCTAssertEqual(data["moderationStatus"] as? String, QuestionModerationStatus.pending.rawValue)
        XCTAssertEqual(data["featuredPlacement"] as? String, QuestionFeaturedPlacement.none.rawValue)
    }

    func testFromFirestoreReadsModerationAndFeaturedPlacement() {
        let moderatedAt = Date(timeIntervalSince1970: 4567)
        let data: [String: Any] = [
            "text": "Which 3 meals would you repeat?",
            "category": "Daily",
            "source": "userCreated",
            "createdAt": Timestamp(date: Date(timeIntervalSince1970: 1234)),
            "createdBy": "user-42",
            "creatorUsername": "ceren",
            "moderationStatus": "rejected",
            "moderatedAt": Timestamp(date: moderatedAt),
            "moderatedBy": "admin-1",
            "rejectionReason": "duplicate",
            "featuredPlacement": "home"
        ]

        let question = Question.fromFirestore(data, id: "question-moderated")

        XCTAssertEqual(question?.moderationStatus, .rejected)
        XCTAssertEqual(question?.moderatedAt, moderatedAt)
        XCTAssertEqual(question?.moderatedBy, "admin-1")
        XCTAssertEqual(question?.rejectionReason, "duplicate")
        XCTAssertEqual(question?.featuredPlacement, .home)
    }

    func testFeaturedOnHomeRequiresApprovedUserCreatedQuestion() {
        let question = Question(
            id: "question-featured",
            text: "Which 3 local places do you recommend?",
            category: "Daily",
            source: .userCreated,
            moderationStatus: .approved,
            featuredPlacement: .home
        )

        XCTAssertTrue(question.isFeaturedOnHome)
    }

    func testCreatorAttributionRequiresUserCreatedQuestionAndUsername() {
        let seededQuestion = Question(
            id: "question-seeded",
            text: "Bugun seni ne mutlu etti?",
            category: "Daily",
            source: .seeded,
            createdBy: "admin-1",
            creatorUsername: "admin"
        )
        let missingUsernameQuestion = Question(
            id: "question-user-created",
            text: "Son zamanlarda seni gulduren 3 sey neydi?",
            category: "Personal",
            source: .userCreated,
            createdBy: "user-123"
        )

        XCTAssertNil(seededQuestion.creatorAttributionUsername)
        XCTAssertNil(missingUsernameQuestion.creatorAttributionUsername)
    }

    func testFromFirestoreReadsExplicitPendingAnnouncementState() {
        let data: [String: Any] = [
            "text": "Seni bu hafta ne heyecanlandirdi?",
            "category": "Daily",
            "source": QuestionSource.seeded.rawValue,
            "isAnnounced": false,
            "createdAt": Timestamp(date: Date())
        ]

        let question = Question.fromFirestore(data, id: "question-pending")

        XCTAssertEqual(question?.isAnnounced, false)
    }

    func testResolvedTextPrefersRequestedLanguageThenFallsBack() {
        let question = Question(
            id: "question-4",
            text: "Merhaba",
            category: "Daily",
            contentId: "daily-01",
            localizedTexts: [
                "tr": "Merhaba",
                "en": "Hello"
            ]
        )

        XCTAssertEqual(question.resolvedText(preferredLanguageCodes: ["en-US"]), "Hello")
        XCTAssertEqual(question.resolvedText(preferredLanguageCodes: ["de-DE"]), "Merhaba")
    }

    func testToFirestoreIncludesContentIdAndLocalizedTexts() {
        let question = Question(
            id: "question-5",
            text: "Bugün seni gülümseten neydi?",
            category: "Daily",
            contentId: "daily-05",
            localizedTexts: [
                "tr": "Bugün seni gülümseten neydi?",
                "en": "What made you smile today?"
            ],
            languageCode: "tr"
        )

        let data = question.toFirestore()

        XCTAssertEqual(data["contentId"] as? String, "daily-05")
        XCTAssertEqual((data["localizedTexts"] as? [String: String])?["en"], "What made you smile today?")
        XCTAssertEqual(data["languageCode"] as? String, "tr")
    }

    func testFromFirestoreReadsLanguageCode() {
        let data: [String: Any] = [
            "text": "Which 3 meals comfort you?",
            "category": "Daily",
            "source": "userCreated",
            "languageCode": "en",
            "createdAt": Timestamp(date: Date())
        ]

        let question = Question.fromFirestore(data, id: "question-language")

        XCTAssertEqual(question?.languageCode, "en")
    }

    func testTrioLanguageVisibilityUsesExplicitLanguageBeforeFallbackText() {
        let question = Question(
            id: "question-trio-language",
            text: "Sizi kötü bir günün ardından rahatlatan ilk 3 yemek hangileri?",
            category: "Daily",
            localizedTexts: ["tr": "Sizi kötü bir günün ardından rahatlatan ilk 3 yemek hangileri?"],
            languageCode: "tr",
            source: .userCreated
        )

        XCTAssertTrue(question.isVisibleInTrio(selectedLanguageCode: "tr"))
        XCTAssertFalse(question.isVisibleInTrio(selectedLanguageCode: "en"))
    }
}
