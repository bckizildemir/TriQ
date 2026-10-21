import Foundation

/// A question-feed snapshot callback that carried neither documents nor an error.
enum QuestionFeedError: LocalizedError {
    case missingSnapshot

    var errorDescription: String? {
        switch self {
        case .missingSnapshot:
            return "The question feed returned no snapshot."
        }
    }
}
