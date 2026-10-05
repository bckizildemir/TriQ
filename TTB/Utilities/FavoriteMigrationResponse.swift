import Foundation

enum FavoriteMigrationResponseError: Error, Equatable {
    case invalidPayload
}

/// Validates the server's per-question migration result before local guest favorites are removed.
///
/// The list is required rather than defaulted to empty: older callable revisions returned only an
/// unavailable count, and treating that response as complete success could silently lose favorites
/// the account never accepted during a mixed client/server rollout.
enum FavoriteMigrationResponse {
    static func unavailableQuestionIDs(
        from data: [String: Any],
        requestedQuestionIDs: [String]
    ) throws -> Set<String> {
        guard let rawUnavailableQuestionIDs = data["unavailableQuestionIds"] as? [String] else {
            throw FavoriteMigrationResponseError.invalidPayload
        }

        let requestedIDs = Set(requestedQuestionIDs)
        let unavailableIDs = Set(rawUnavailableQuestionIDs)
        guard unavailableIDs.isSubset(of: requestedIDs) else {
            throw FavoriteMigrationResponseError.invalidPayload
        }

        return unavailableIDs
    }
}
