import Foundation

enum FavoriteToggleResponseError: Error, Equatable {
    case invalidPayload
}

enum FavoriteToggleResponse {
    static func parseBool(from value: Any?) -> Bool? {
        if let bool = value as? Bool {
            return bool
        }
        if let number = value as? NSNumber {
            switch number.doubleValue {
            case 0:
                return false
            case 1:
                return true
            default:
                return nil
            }
        }
        return nil
    }

    static func resolve(
        data: [String: Any],
        currentFavoriteState: Bool?
    ) throws -> Bool {
        if let rawIsFavorite = data["isFavorite"] {
            guard let isFavorite = parseBool(from: rawIsFavorite) else {
                throw FavoriteToggleResponseError.invalidPayload
            }
            return isFavorite
        }

        if let currentFavoriteState {
            return !currentFavoriteState
        }

        throw FavoriteToggleResponseError.invalidPayload
    }
}
