/// The four Firestore question feeds `QuestionModel` listens to. A seam so a test can drive the
/// model's listener setup without Firebase.
///
/// `Sendable` because the `@MainActor` `QuestionModel` hands this existential to `nonisolated async`
/// requirements. `QuestionService` and the test fake are both `actor`s. Each `completion` runs on
/// the main actor. The three question feeds deliver a `Result`: a listener error arrives as a
/// `.failure`, so the model can end its loading state.
protocol QuestionFeedListening: Sendable {
    func setupSeededQuestionsListener(
        completion: @escaping @MainActor @Sendable (Result<[Question], any Error>) -> Void
    ) async -> FirestoreListenerHandle

    func setupFeaturedHomeQuestionsListener(
        completion: @escaping @MainActor @Sendable (Result<[Question], any Error>) -> Void
    ) async -> FirestoreListenerHandle

    func setupTrioQuestionsListener(
        completion: @escaping @MainActor @Sendable (Result<[Question], any Error>) -> Void
    ) async -> FirestoreListenerHandle

    /// Returns nil when no user is signed in.
    func setupUserAnswersListener(
        completion: @escaping @MainActor @Sendable ([String: UserAnswer]) -> Void
    ) async -> FirestoreListenerHandle?
}

extension QuestionService: QuestionFeedListening {}
