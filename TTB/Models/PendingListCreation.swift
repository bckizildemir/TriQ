import Foundation

/// A question list the user asked for that the server has not confirmed yet.
///
/// It lives in `QuestionListStore.pendingCreations`, never in `lists`, so an authoritative snapshot
/// can neither drop nor duplicate it.
struct PendingListCreation: Identifiable, Equatable {
    enum State: Equatable {
        case saving
        case failed

        var title: String {
            switch self {
            case .saving:
                String(localized: "questionLists.pending.saving")
            case .failed:
                String(localized: "questionLists.pending.notSaved")
            }
        }
    }

    /// Local id. It has no relation to the id the server gives the list.
    let id: UUID
    let name: String
    /// The question the "New list + add this question" action adds once the list exists.
    let questionIDToAdd: String?
    var state: State = .saving
}

/// A background failure that the user must hear about, because the screen that started it is gone.
enum QuestionListCreationFailure: Equatable {
    case createFailed
    case addQuestionFailed

    var message: String {
        switch self {
        case .createFailed:
            String(localized: "questionLists.error.createFailed")
        case .addQuestionFailed:
            String(localized: "questionLists.error.addQuestionFailed")
        }
    }
}
