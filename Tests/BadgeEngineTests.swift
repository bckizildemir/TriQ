import XCTest
@testable import TTB

final class BadgeEngineTests: XCTestCase {
    
    // MARK: - Badge Type Tests
    
    func testBadgeTypeFirestoreRawValueContractAndRejectsUnknownValues() {
        let persistedValues: [(BadgeType, String)] = [
            (.total, "total"),
            (.category, "category"),
            (.streak, "streak"),
        ]

        for (type, rawValue) in persistedValues {
            XCTAssertEqual(type.rawValue, rawValue)
            XCTAssertEqual(BadgeType(rawValue: rawValue), type)
        }
        XCTAssertNil(BadgeType(rawValue: "invalid"))
    }
    
    func testBadgeFirestoreSerialization() {
        let badge = Badge(
            id: "test_badge",
            title: "Test Badge",
            description: "Test Description",
            icon: "star.fill",
            isLocked: true,
            requirement: "Test requirement",
            progress: 0.5,
            targetCount: 10,
            type: .category,
            category: "Daily"
        )
        
        let firestoreData = badge.toFirestore()
        
        XCTAssertEqual(firestoreData["title"] as? String, "Test Badge")
        XCTAssertEqual(firestoreData["description"] as? String, "Test Description")
        XCTAssertEqual(firestoreData["icon"] as? String, "star.fill")
        XCTAssertEqual(firestoreData["requirement"] as? String, "Test requirement")
        XCTAssertEqual(firestoreData["targetCount"] as? Int, 10)
        XCTAssertEqual(firestoreData["type"] as? String, "category")
        XCTAssertEqual(firestoreData["category"] as? String, "Daily")
    }
    
    func testBadgeFirestoreDeserialization() {
        let firestoreData: [String: Any] = [
            "title": "Test Badge",
            "description": "Test Description",
            "icon": "star.fill",
            "requirement": "Test requirement",
            "targetCount": 10,
            "type": "streak",
            "unlocked": true,
            "progress": 0.75
        ]
        
        let badge = Badge.fromFirestore(firestoreData, id: "test_badge")
        
        XCTAssertNotNil(badge)
        XCTAssertEqual(badge?.id, "test_badge")
        XCTAssertEqual(badge?.title, "Test Badge")
        XCTAssertEqual(badge?.description, "Test Description")
        XCTAssertEqual(badge?.icon, "star.fill")
        XCTAssertFalse(badge?.isLocked ?? true) // unlocked: true means isLocked: false
        XCTAssertEqual(badge?.requirement, "Test requirement")
        XCTAssertEqual(badge?.progress, 0.75)
        XCTAssertEqual(badge?.targetCount, 10)
        XCTAssertEqual(badge?.type, .streak)
    }

    func testBadgeLocalizationPrefersRequestedLanguageThenFallsBack() {
        let badge = Badge(
            id: "localized_badge",
            title: "İlk Adım",
            description: "İlk sorunuzu cevapladınız.",
            icon: "1.circle.fill",
            isLocked: false,
            requirement: "1 soru cevaplayın",
            progress: 1,
            targetCount: 1,
            type: .total,
            titleLocalizations: ["tr": "İlk Adım", "en": "First Step"],
            descriptionLocalizations: ["tr": "İlk sorunuzu cevapladınız.", "en": "You answered your first question."],
            requirementLocalizations: ["tr": "1 soru cevaplayın", "en": "Answer 1 question"]
        )

        XCTAssertEqual(badge.resolvedTitle(preferredLanguageCodes: ["en-US"]), "First Step")
        XCTAssertEqual(badge.resolvedDescription(preferredLanguageCodes: ["de-DE"]), "İlk sorunuzu cevapladınız.")
        XCTAssertEqual(badge.resolvedRequirement(preferredLanguageCodes: ["en"]), "Answer 1 question")
    }

    func testBadgeFirestoreSerializationIncludesLocalizationMaps() {
        let badge = Badge(
            id: "localized_badge",
            title: "İlk Adım",
            description: "İlk sorunuzu cevapladınız.",
            icon: "1.circle.fill",
            isLocked: false,
            requirement: "1 soru cevaplayın",
            progress: 1,
            targetCount: 1,
            type: .total,
            titleLocalizations: ["en": "First Step"],
            descriptionLocalizations: ["en": "You answered your first question."],
            requirementLocalizations: ["en": "Answer 1 question"]
        )

        let data = badge.toFirestore()

        XCTAssertEqual((data["titleLocalizations"] as? [String: String])?["en"], "First Step")
        XCTAssertEqual((data["descriptionLocalizations"] as? [String: String])?["en"], "You answered your first question.")
        XCTAssertEqual((data["requirementLocalizations"] as? [String: String])?["en"], "Answer 1 question")
    }

    func testBadgeProgressPresentationFormatsQuestionBadges() {
        let badge = Badge(
            id: "career_focused",
            title: "Kariyer Odaklı",
            description: "Kariyer kategorisinde 10 soru cevapladınız.",
            icon: "briefcase.fill",
            isLocked: true,
            requirement: "Kariyer kategorisinde 10 soru cevaplayın",
            progress: 0.4,
            targetCount: 10,
            type: .category,
            category: "Career"
        )

        let presentation = badge.progressPresentation(preferredLanguageCodes: ["tr"])

        XCTAssertEqual(presentation?.currentCount, 4)
        XCTAssertEqual(presentation?.displayText, "4 / 10 soru")
        XCTAssertEqual(presentation?.accessibilityValue, "4 / 10 soru")
        XCTAssertEqual(presentation?.showsProgressBar, true)
    }

    func testBadgeProgressPresentationFormatsStreakBadges() {
        let badge = Badge(
            id: "streak_badge",
            title: "Steady",
            description: "Keep your streak going.",
            icon: "flame.fill",
            isLocked: true,
            requirement: "Maintain a 7 day streak",
            progress: 3.0 / 7.0,
            targetCount: 7,
            type: .streak
        )

        let presentation = badge.progressPresentation(preferredLanguageCodes: ["en"])

        XCTAssertEqual(presentation?.currentCount, 3)
        XCTAssertEqual(presentation?.displayText, "3 / 7 days")
        XCTAssertEqual(presentation?.showsProgressBar, true)
    }

    func testBadgeProgressPresentationClampsCompletedAndOverflowCounts() {
        let completedBadge = Badge(
            id: "completed_badge",
            title: "Completed",
            description: "Completed",
            icon: "star.fill",
            isLocked: false,
            requirement: "Answer 10 questions",
            progress: 1.0,
            targetCount: 10,
            type: .total
        )
        let overflowBadge = Badge(
            id: "overflow_badge",
            title: "Overflow",
            description: "Overflow",
            icon: "star.fill",
            isLocked: false,
            requirement: "Answer 10 questions",
            progress: 1.8,
            targetCount: 10,
            type: .total
        )

        let completedPresentation = completedBadge.progressPresentation(preferredLanguageCodes: ["en"])
        let overflowPresentation = overflowBadge.progressPresentation(preferredLanguageCodes: ["en"])

        XCTAssertEqual(completedPresentation?.currentCount, 10)
        XCTAssertEqual(completedPresentation?.displayText, "10 / 10 questions")
        XCTAssertEqual(completedPresentation?.showsProgressBar, false)
        XCTAssertEqual(overflowPresentation?.currentCount, 10)
        XCTAssertEqual(overflowPresentation?.displayText, "10 / 10 questions")
    }

    func testBadgeProgressPresentationClampsNegativeCountsAtZero() {
        let badge = Badge(
            id: "negative_badge",
            title: "Negative",
            description: "Negative",
            icon: "star.fill",
            isLocked: true,
            requirement: "Answer 10 questions",
            progress: -0.2,
            targetCount: 10,
            type: .total
        )

        let presentation = badge.progressPresentation(preferredLanguageCodes: ["en"])

        XCTAssertEqual(presentation?.currentCount, 0)
        XCTAssertEqual(presentation?.displayText, "0 / 10 questions")
        XCTAssertEqual(presentation?.showsProgressBar, true)
    }

    func testBadgeProgressPresentationTreatsNonFiniteProgressAsZero() {
        for progress in [Double.nan, .infinity, -.infinity] {
            let badge = Badge(
                id: "corrupted_badge",
                title: "Corrupted",
                description: "Corrupted",
                icon: "star.fill",
                isLocked: true,
                requirement: "Answer 10 questions",
                progress: progress,
                targetCount: 10,
                type: .total
            )

            let presentation = badge.progressPresentation(preferredLanguageCodes: ["en"])

            XCTAssertEqual(presentation?.currentCount, 0)
            XCTAssertEqual(presentation?.displayText, "0 / 10 questions")
        }
    }

    func testBadgeProgressPresentationReturnsNilForZeroTargetCount() {
        let badge = Badge(
            id: "zero_target",
            title: "Zero",
            description: "Zero",
            icon: "star.fill",
            isLocked: true,
            requirement: "Answer questions",
            progress: 0.5,
            targetCount: 0,
            type: .total
        )

        XCTAssertNil(badge.progressPresentation(preferredLanguageCodes: ["en"]))
    }
    func testBadgeProgressCalculatorClampsInvalidAndBoundaryCounts() {
        let cases: [(current: Int, target: Int, expected: Double)] = [
            (-1, 10, 0),
            (5, 0, 0),
            (0, 10, 0),
            (5, 10, 0.5),
            (10, 10, 1),
            (Int.max, 10, 1),
        ]

        for testCase in cases {
            XCTAssertEqual(
                BadgeProgressCalculator.progress(
                    currentCount: testCase.current,
                    targetCount: testCase.target
                ),
                testCase.expected,
                accuracy: 0.000_001
            )
        }
    }

    func testAnswerCounterIncrementNormalizesCorruptionAndSaturatesOverflow() {
        let cases: [(stored: Int, expected: Int)] = [
            (.min, 1),
            (0, 1),
            (41, 42),
            (.max - 1, .max),
            (.max, .max),
        ]

        for testCase in cases {
            XCTAssertEqual(
                AnswerCounterCalculator.incremented(testCase.stored),
                testCase.expected
            )
        }
    }

    func testCurrentStreakDeduplicatesDaysAndStopsAtGapAcrossDST() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        let latest = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 3, day: 9, hour: 1))
        )
        let previous = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 23))
        )
        let gap = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 3, day: 6, hour: 12))
        )

        let streak = AnswerStreakCalculator.currentStreak(
            from: [gap, previous, latest, latest],
            calendar: calendar
        )

        XCTAssertEqual(streak, 2)
    }

    func testUpdatedStreakUsesCalendarDaysAndSaturatesCorruptedCount() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/Istanbul"))
        let beforeMidnight = try XCTUnwrap(
            calendar.date(from: DateComponents(
                year: 2026,
                month: 7,
                day: 26,
                hour: 23,
                minute: 59
            ))
        )
        let afterMidnight = try XCTUnwrap(
            calendar.date(from: DateComponents(
                year: 2026,
                month: 7,
                day: 27,
                hour: 0,
                minute: 1
            ))
        )

        XCTAssertEqual(
            AnswerStreakCalculator.updatedStreak(
                from: beforeMidnight,
                currentStreak: .max,
                now: afterMidnight,
                calendar: calendar
            ),
            .max
        )
    }
}
