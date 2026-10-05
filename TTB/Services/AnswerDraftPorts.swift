import Foundation

// The four things `AnswerDraftStore` needs from the rest of the app in order to save an answer.
//
// Each is deliberately the narrowest surface that does the job. `AnswerPersisting` in particular is
// one method rather than a protocol over all of `QuestionService`: the collapsed save path makes
// exactly one persistence call, and abstracting the other ~30 methods would drag Firestore listener
// handles into a change that has nothing to do with them.
//
// The point of all four is the same as `FavoriteServicing`'s: with in-memory fakes, the optimistic
// write, the rollback, the upload fan-out and the compare-and-swap can all be exercised without
// Firebase — none of which was reachable before, because `questionService` was a concrete optional
// and every test ran the branch where persistence silently did nothing.

/// Writes an answer to the backend.
///
/// Takes a ``NormalizedAnswer`` and nothing else, so a raw draft cannot reach the wire and there is
/// no order to get wrong.
/// `Sendable` because a save crosses concurrency domains: the store is main-actor, the adapters are
/// actors, and the uploads run in a task group.
protocol AnswerPersisting: Sendable {
    func save(_ answer: NormalizedAnswer, for questionId: String) async throws
}

/// Uploads and removes the images belonging to an answer.
protocol AnswerImageStoring: Sendable {
    /// Uploads one image and reports how it went.
    ///
    /// Returns rather than throws: these run concurrently, and one slot failing must not cancel the
    /// others or lose the URLs that did arrive.
    func upload(_ upload: AnswerImageUpload, questionId: String) async -> AnswerImageUploadOutcome

    /// Deletes the image in one slot. Used to clean up after an image the user removed.
    func deleteAnswerImage(questionId: String, slotIndex: Int) async throws
}

/// Reads and writes the locally cached answer for a question.
///
/// The cache stays in `QuestionModel`, where its eleven readers and the Firestore listener that
/// feeds it already are. The store reaches it through this port instead of owning it, because
/// rollback and compare-and-swap need *access* to that state, not ownership of it.
@MainActor
protocol AnswerCaching: AnyObject {
    /// What is cached, in its stored form.
    ///
    /// Returns `UserAnswer` rather than a ``NormalizedAnswer`` so a rollback can put back exactly what
    /// was there — same `answeredAt`, same user id — instead of a value that would read as a fresh
    /// answer. `FavoriteServicing` speaks `Question` for the same reason: these are the app's own model
    /// types, not backend ones.
    func currentAnswer(for questionId: String) -> UserAnswer?

    /// Stores an answer, stamping it as answered now.
    func cache(_ answer: NormalizedAnswer, for questionId: String)

    /// Puts back what ``currentAnswer(for:)`` previously returned, or clears the entry when there was
    /// nothing there before.
    func restore(_ previous: UserAnswer?, for questionId: String)
}

/// Where a save reports failure.
///
/// A save outlives the editor that started it — the sheet dismisses and uploads carry on — so there
/// is no view left to hand an error back to. This is why failures land on an app-level surface.
@MainActor
protocol AnswerSaveErrorReporting: AnyObject {
    func report(_ error: AnswerSaveError)
}

/// What `AnswerDraftStore` needs from the object holding the answer being edited.
///
/// One parameter instead of two, since `QuestionModel` is both.
typealias AnswerDraftHost = AnswerCaching & AnswerSaveErrorReporting

/// What can go wrong while saving an answer.
///
/// Typed rather than pre-localized, so the store stays free of `AppLocalization` and tests assert on
/// which failure happened instead of on user-facing copy that translation would break.
enum AnswerSaveError: Equatable {
    /// The write that was supposed to store the text failed. The optimistic cache is rolled back.
    case textSaveFailed

    /// The text is stored, but the follow-up write carrying the image URLs failed.
    case imageURLSaveFailed

    /// One slot's image did not upload. The rest of the answer is unaffected.
    case imageUploadFailed(slotIndex: Int, underlyingDescription: String)
}

// MARK: - Live adapters

extension QuestionService: AnswerPersisting {
    func save(_ answer: NormalizedAnswer, for questionId: String) async throws {
        try await saveAnswers(
            answer.texts,
            imageURLs: answer.urls,
            imageAttributions: answer.attributions,
            for: questionId
        )
    }
}

/// The real image store: photo-library picks go to Storage, suggestions are copied server-side.
///
/// Holding both services is why this is a type rather than an extension on `ImageService` — the two
/// halves of "upload this slot's image" live in different services.
///
/// `suggestionService` has no default on purpose. It used to default to a launch-argument check —
/// a copy of the one in `QuestionCardExpandedView` — so this type decided for itself whether it ran
/// inside a UI test. AD-3 made that a wiring decision: every caller states which service it has, and
/// `AppEnvironment` is where the answer comes from.
struct LiveAnswerImageStore: AnswerImageStoring {
    private let imageService: ImageService
    private let suggestionService: AnswerImageSuggestionService?

    init(
        imageService: ImageService = .shared,
        suggestionService: AnswerImageSuggestionService?
    ) {
        self.imageService = imageService
        self.suggestionService = suggestionService
    }

    func upload(_ upload: AnswerImageUpload, questionId: String) async -> AnswerImageUploadOutcome {
        do {
            switch upload.source {
            case let .local(image):
                let url = try await imageService.uploadAnswerImage(
                    image,
                    questionId: questionId,
                    slotIndex: upload.slotIndex
                )
                return .uploaded(slotIndex: upload.slotIndex, url: url, attribution: nil)

            case let .suggestion(suggestion):
                guard let suggestionService else {
                    return .failed(slotIndex: upload.slotIndex, error: ImageServiceError.invalidURL)
                }
                let saved = try await suggestionService.saveSuggestedImage(
                    suggestion,
                    questionId: questionId,
                    slotIndex: upload.slotIndex
                )
                return .uploaded(
                    slotIndex: upload.slotIndex,
                    url: saved.downloadURL,
                    attribution: saved.attribution ?? suggestion.attribution
                )
            }
        } catch {
            return .failed(slotIndex: upload.slotIndex, error: error)
        }
    }

    func deleteAnswerImage(questionId: String, slotIndex: Int) async throws {
        try await imageService.deleteAnswerImage(questionId: questionId, slotIndex: slotIndex)
    }
}

// `QuestionModel`'s own adapters — ``AnswerCaching`` and ``AnswerSaveErrorReporting`` — live in
// `QuestionModel.swift` rather than here. `currentUserAnswers` is `private(set)`, so only that file
// can write the cache, which is the right place for the adapter that owns writing it anyway.
