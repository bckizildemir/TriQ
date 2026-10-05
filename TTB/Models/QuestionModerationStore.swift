import FirebaseAuth
import Foundation

/// Owns the moderation corpus and the choreography behind every admin action.
///
/// This is AD-4's split. Eight members used to sit on `QuestionModel` — `refreshAdminQuestions`,
/// `addQuestion`, `deleteQuestion`, `approveQuestion`, `rejectQuestion`, `setFeaturedPlacement`,
/// `editQuestion` and a private `updateQuestion` — together with two private question-copy builders
/// and the `upsertLocalQuestion`/`removeLocalQuestion` pair that patched the app's read caches after
/// each write.
///
/// The corpus here is deliberately **not** the app's read model, and that separation is the fix rather
/// than a side effect. `QuestionModel` builds its `questions` from two Firestore listeners whose
/// queries already exclude unapproved content; `refreshAdminQuestions` replaced that with the whole
/// unfiltered collection and then recomputed `groupedQuestions` from it, so opening the admin screen
/// carried pending and rejected questions onto `CategoryQuestionsView` and `HomeView` until a listener
/// snapshot happened to fire.
///
/// Every write is backend-first: the store patches its corpus only after the write succeeds, so a
/// rejected write cannot leave an admin looking at a decision the backend refused. There is no
/// optimistic path and therefore no rollback — an admin action is a deliberate act on one row, not a
/// tap that must feel instant.
@MainActor
final class QuestionModerationStore: ObservableObject {

    /// The whole `questions` collection as of the last `refresh()`, plus the patches applied since.
    ///
    /// Unsorted and unfiltered on purpose: `AdminQuestionView` filters by moderation status and sorts
    /// what survives, and it counts over the unsorted corpus.
    @Published private(set) var questions: [Question] = []

    private let service: QuestionModerating
    private let currentModeratorID: () -> String?
    private let now: () -> Date

    /// `currentModeratorID` and `now` are injected rather than read from ambient state, which is what
    /// makes the moderation stamp assertable. The old code read `Auth.auth().currentUser?.uid` twice
    /// per decision — once for the backend payload and once for the local copy — so the two could
    /// disagree in principle and no test could reach either.
    init(
        service: QuestionModerating,
        currentModeratorID: @escaping () -> String? = { Auth.auth().currentUser?.uid },
        now: @escaping () -> Date = Date.init
    ) {
        self.service = service
        self.currentModeratorID = currentModeratorID
        self.now = now
    }

    // MARK: - Reads

    /// Replaces the corpus with the backend's.
    ///
    /// Throws rather than swallowing, unlike `refreshAdminQuestions`, which wrote the message into
    /// `QuestionModel.error` — a property the admin screen never reads and `CategoryQuestionsView`
    /// alerts on. So a failed admin refresh used to interrupt a user screen and leave the admin list
    /// silently stale.
    func refresh() async throws {
        questions = try await service.allQuestions()
    }

    /// Resolves one row of the corpus.
    ///
    /// The admin detail screen needs this and cannot use `QuestionModel.question(withID:)`, which
    /// searches the read model — where a pending or rejected question does not appear. Reaching for it
    /// there is what the split has to stop: the detail screen exists precisely for the rows the read
    /// model excludes.
    func question(withID questionID: String) -> Question? {
        questions.first { $0.id == questionID }
    }

    // MARK: - Moderation decisions

    func approve(_ question: Question) async throws {
        try await recordDecision(.approved, for: question, reason: nil)
    }

    func reject(_ question: Question, reason: String?) async throws {
        try await recordDecision(.rejected, for: question, reason: reason)
    }

    private func recordDecision(
        _ status: QuestionModerationStatus,
        for question: Question,
        reason: String?
    ) async throws {
        let moderatorID = currentModeratorID()

        try await service.updateModeration(
            questionId: question.id,
            status: status,
            rejectionReason: reason,
            moderatedBy: moderatorID
        )

        // The reason is sent to the backend untrimmed and trimmed locally, because
        // `Question.moderated` and the backend write apply the same trim independently. They agree by
        // test, not by sharing code — the backend payload needs `FieldValue.delete()` for an absent
        // reason, which no `Question` can express.
        upsert(
            question.moderated(
                as: status,
                at: now(),
                by: moderatorID,
                rejectionReason: reason
            )
        )
    }

    func setFeaturedPlacement(
        _ placement: QuestionFeaturedPlacement,
        for question: Question
    ) async throws {
        try await service.updateFeaturedPlacement(questionId: question.id, placement: placement)
        upsert(question.featured(as: placement))
    }

    // MARK: - Content changes

    /// `languageCode` is the language the admin is typing in, passed in rather than read from
    /// `AppLocalization` so the merge is assertable without a locale.
    func edit(
        _ question: Question,
        newText: String,
        newCategory: String,
        languageCode: String
    ) async throws {
        let edited = question.edited(
            text: newText,
            category: newCategory,
            languageCode: languageCode
        )
        try await service.update(edited)
        upsert(edited)
    }

    func add(_ question: Question) async throws {
        try await service.add(question)
        upsert(question)
    }

    func delete(_ question: Question) async throws {
        try await service.delete(id: question.id)
        questions.removeAll { $0.id == question.id }
    }

    // MARK: - Corpus patching

    /// A linear scan, unlike `QuestionModel`'s id index. One admin action patches one row, so there is
    /// no per-card lookup to amortize here — the index existed because every rendered card called
    /// `question(withID:)`.
    ///
    /// An unknown question is appended rather than dropped: the screen can hold a `Question` value
    /// that predates the last refresh, and losing the patch would make the action look inert.
    private func upsert(_ question: Question) {
        if let index = questions.firstIndex(where: { $0.id == question.id }) {
            questions[index] = question
        } else {
            questions.append(question)
        }
    }
}
