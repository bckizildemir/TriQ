import XCTest
@testable import TTB

/// The three named moderation operations on `Question`, which replace `QuestionModel`'s
/// `copiedQuestion`/`moderatedQuestion` pair and `editQuestion`'s inline 25-line initializer.
///
/// These rules had no coverage before. They lived in a private helper reachable only through
/// `@MainActor` admin methods that call Firestore, and the local copy they produce is what the admin
/// list renders until a listener snapshot arrives — so a divergence from the backend showed up as a
/// row that looked wrong and then silently corrected itself.
///
/// The assertions are written against what `QuestionService.updateQuestionModeration` actually writes,
/// because those two must agree. Where they disagreed, the service is treated as correct: it is the
/// write that survives.
final class QuestionModerationOperationsTests: XCTestCase {

    private let moderatedAt = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: - moderated(as:at:by:rejectionReason:)

    func testApprovingRecordsTheDecisionAndItsAuthor() {
        let question = self.question(moderationStatus: .pending)

        let moderated = question.moderated(as: .approved, at: moderatedAt, by: "admin-1")

        XCTAssertEqual(moderated.moderationStatus, .approved)
        XCTAssertEqual(moderated.moderatedAt, moderatedAt)
        XCTAssertEqual(moderated.moderatedBy, "admin-1")
    }

    func testApprovingClearsAnEarlierRejectionReason() {
        let question = self.question(moderationStatus: .rejected, rejectionReason: "off topic")

        let moderated = question.moderated(as: .approved, at: moderatedAt, by: "admin-1")

        XCTAssertNil(moderated.rejectionReason)
    }

    func testApprovingLeavesTheFeaturedPlacementAlone() {
        let question = self.question(moderationStatus: .pending, featuredPlacement: .home)

        let moderated = question.moderated(as: .approved, at: moderatedAt, by: "admin-1")

        XCTAssertEqual(moderated.featuredPlacement, .home)
    }

    func testRejectingTrimsTheReason() {
        let question = self.question(moderationStatus: .pending)

        let moderated = question.moderated(
            as: .rejected,
            at: moderatedAt,
            by: "admin-1",
            rejectionReason: "   duplicate   "
        )

        XCTAssertEqual(moderated.rejectionReason, "duplicate")
    }

    func testRejectingWithBlankReasonStoresNilRatherThanAnEmptyString() {
        let question = self.question(moderationStatus: .pending)

        let moderated = question.moderated(
            as: .rejected,
            at: moderatedAt,
            by: "admin-1",
            rejectionReason: "   \n  "
        )

        XCTAssertNil(moderated.rejectionReason)
    }

    /// `QuestionService.updateQuestionModeration` writes
    /// `featuredPlacement = .none` for a rejection, so the local copy must too — otherwise a rejected
    /// question keeps rendering as featured until a listener snapshot corrects it.
    func testRejectingWithdrawsTheQuestionFromItsFeaturedPlacement() {
        let question = self.question(moderationStatus: .approved, featuredPlacement: .home)

        let moderated = question.moderated(as: .rejected, at: moderatedAt, by: "admin-1")

        XCTAssertEqual(moderated.featuredPlacement, .none)
    }

    /// The divergence this operation closes. The service clears the placement for `.pending` as well
    /// as `.rejected`, but the caller only ever passed `.none` for a rejection, so sending a question
    /// back to `.pending` left the local copy claiming a placement the backend had already dropped.
    /// No screen reaches `.pending` today, which is why nothing caught it.
    func testReturningAQuestionToPendingAlsoWithdrawsItsFeaturedPlacement() {
        let question = self.question(moderationStatus: .approved, featuredPlacement: .home)

        let moderated = question.moderated(as: .pending, at: moderatedAt, by: "admin-1")

        XCTAssertEqual(moderated.featuredPlacement, .none)
    }

    func testModeratingPreservesEverythingItDoesNotDecide() {
        let createdAt = Date(timeIntervalSince1970: 1_600_000_000)
        let question = Question(
            id: "q1",
            text: "legacy text",
            category: "Daily",
            contentId: "content-1",
            localizedTexts: ["en": "English", "tr": "Türkçe"],
            languageCode: "tr",
            source: .userCreated,
            answers: ["a", "b", "c"],
            isFavorite: true,
            createdAt: createdAt,
            createdBy: "user-1",
            creatorUsername: "berke",
            isAnnounced: true,
            moderationStatus: .pending,
            lastAnsweredAt: createdAt,
            announcedAt: createdAt,
            announcedInReleaseId: "release-1",
            totalRespondents: 12,
            todayRespondents: 3,
            todayDate: "2026-07-31",
            answerStats: ["0": ["Mavi": 5]]
        )

        let moderated = question.moderated(as: .approved, at: moderatedAt, by: "admin-1")

        XCTAssertEqual(moderated.id, "q1")
        XCTAssertEqual(moderated.fallbackText, "legacy text")
        XCTAssertEqual(moderated.category, "Daily")
        XCTAssertEqual(moderated.contentId, "content-1")
        XCTAssertEqual(moderated.localizedTexts, ["en": "English", "tr": "Türkçe"])
        XCTAssertEqual(moderated.languageCode, "tr")
        XCTAssertEqual(moderated.source, .userCreated)
        XCTAssertEqual(moderated.answers, ["a", "b", "c"])
        XCTAssertTrue(moderated.isFavorite)
        XCTAssertEqual(moderated.createdAt, createdAt)
        XCTAssertEqual(moderated.createdBy, "user-1")
        XCTAssertEqual(moderated.creatorUsername, "berke")
        XCTAssertTrue(moderated.isAnnounced)
        XCTAssertEqual(moderated.lastAnsweredAt, createdAt)
        XCTAssertEqual(moderated.announcedAt, createdAt)
        XCTAssertEqual(moderated.announcedInReleaseId, "release-1")
        XCTAssertEqual(moderated.totalRespondents, 12)
        XCTAssertEqual(moderated.todayRespondents, 3)
        XCTAssertEqual(moderated.todayDate, "2026-07-31")
        XCTAssertEqual(moderated.answerStats, ["0": ["Mavi": 5]])
    }

    /// A `nil` moderator id is a real state — the admin methods read it from ambient auth, which can
    /// be nil. The operation must not invent an empty string, because the backend distinguishes them.
    func testAnUnknownModeratorStaysNil() {
        let question = self.question(moderationStatus: .pending)

        let moderated = question.moderated(as: .approved, at: moderatedAt, by: nil)

        XCTAssertNil(moderated.moderatedBy)
    }

    // MARK: - featured(as:)

    func testFeaturingChangesOnlyThePlacement() {
        let question = self.question(moderationStatus: .approved, featuredPlacement: .none)

        let featured = question.featured(as: .home)

        XCTAssertEqual(featured.featuredPlacement, .home)
        XCTAssertEqual(featured.moderationStatus, .approved)
        XCTAssertNil(featured.moderatedAt)
        XCTAssertNil(featured.moderatedBy)
    }

    func testFeaturingKeepsAnExistingRejectionReason() {
        let question = self.question(moderationStatus: .rejected, rejectionReason: "off topic")

        let featured = question.featured(as: .none)

        XCTAssertEqual(featured.rejectionReason, "off topic")
    }

    // MARK: - edited(text:category:languageCode:)

    func testEditingWritesTheNewTextForTheGivenLanguageAndKeepsTheOthers() {
        let question = self.question(
            localizedTexts: ["en": "Old English", "tr": "Eski Türkçe"],
            languageCode: "tr"
        )

        let edited = question.edited(text: "New English", category: "Daily", languageCode: "en")

        XCTAssertEqual(edited.localizedTexts, ["en": "New English", "tr": "Eski Türkçe"])
    }

    func testEditingReplacesTheFallbackTextSoAReaderWithNoMatchingLanguageSeesTheEdit() {
        let question = self.question(localizedTexts: [:], languageCode: nil)

        let edited = question.edited(text: "New text", category: "Daily", languageCode: "en")

        XCTAssertEqual(edited.fallbackText, "New text")
    }

    func testEditingChangesTheCategory()  {
        let question = self.question(category: "Daily")

        let edited = question.edited(text: "Unchanged?", category: "Personal", languageCode: "en")

        XCTAssertEqual(edited.category, "Personal")
    }

    /// `editQuestion` used `question.languageCode ?? AppLocalization.currentLanguageCode`, so a
    /// question decoded without a language code got one from the editor's locale. Keep that.
    func testEditingAdoptsTheEditingLanguageWhenTheQuestionHasNone() {
        let question = self.question(localizedTexts: [:], languageCode: nil)

        let edited = question.edited(text: "New text", category: "Daily", languageCode: "en")

        XCTAssertEqual(edited.languageCode, "en")
    }

    func testEditingLeavesAnExistingLanguageCodeAlone() {
        let question = self.question(localizedTexts: ["tr": "Eski"], languageCode: "tr")

        let edited = question.edited(text: "New English", category: "Daily", languageCode: "en")

        XCTAssertEqual(edited.languageCode, "tr")
    }

    func testEditingDoesNotTouchTheModerationDecision() {
        let question = self.question(
            moderationStatus: .approved,
            featuredPlacement: .home,
            rejectionReason: "stale"
        )

        let edited = question.edited(text: "New text", category: "Daily", languageCode: "en")

        XCTAssertEqual(edited.moderationStatus, .approved)
        XCTAssertEqual(edited.featuredPlacement, .home)
        XCTAssertEqual(edited.rejectionReason, "stale")
    }

    // MARK: - Helper

    private func question(
        category: String = "Daily",
        localizedTexts: [String: String] = ["en": "Question?"],
        languageCode: String? = "en",
        moderationStatus: QuestionModerationStatus = .pending,
        featuredPlacement: QuestionFeaturedPlacement = .none,
        rejectionReason: String? = nil
    ) -> Question {
        Question(
            id: "q1",
            text: "Question?",
            category: category,
            localizedTexts: localizedTexts,
            languageCode: languageCode,
            source: .userCreated,
            createdAt: Date(timeIntervalSince1970: 1_600_000_000),
            moderationStatus: moderationStatus,
            rejectionReason: rejectionReason,
            featuredPlacement: featuredPlacement
        )
    }
}
