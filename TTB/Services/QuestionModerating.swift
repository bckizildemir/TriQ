import Foundation

/// Everything `QuestionModerationStore` needs from the backend to own the moderation corpus.
///
/// Two adapters satisfy it: `QuestionService` in the app, and an in-memory fake in the tests. The
/// fake is the point, and the same point `FavoriteServicing` makes: the write-then-patch choreography
/// behind every admin action had no coverage while it sat on `QuestionModel`, because reaching it
/// meant reaching Firestore.
///
/// The operations are one-for-one with the `QuestionService` methods they wrap rather than fewer and
/// wider, because each maps to a distinct Firestore write with its own field rules — and those rules
/// are what `Question`'s moderation operations mirror locally. Collapsing them would put the store in
/// the business of deciding which write to make.
protocol QuestionModerating {
    /// The whole `questions` collection, unfiltered — pending and rejected included.
    ///
    /// This is the corpus a moderation screen exists to work through, and it is deliberately not the
    /// app's read model. `QuestionModel` builds that from two query-filtered listeners; feeding this
    /// result into it is what used to carry unapproved questions onto the category screens.
    func allQuestions() async throws -> [Question]

    func add(_ question: Question) async throws

    /// Writes the whole question. Used for an admin text or category edit.
    func update(_ question: Question) async throws

    func delete(id questionId: String) async throws

    /// Records a moderation decision. The backend applies the same two rules
    /// `Question.moderated(as:at:by:rejectionReason:)` applies locally: a reason belongs only to a
    /// rejection, and neither a rejected nor a pending question keeps a featured placement.
    func updateModeration(
        questionId: String,
        status: QuestionModerationStatus,
        rejectionReason: String?,
        moderatedBy: String?
    ) async throws

    func updateFeaturedPlacement(
        questionId: String,
        placement: QuestionFeaturedPlacement
    ) async throws
}
