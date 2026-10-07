#if DEBUG
import Foundation

/// In-memory adapter at the favorites seam, for UI-test harnesses.
///
/// The harnesses run on fixture data, so they need a `FavoriteServicing` that answers from memory.
/// Toggles are applied locally and re-published to the listener, so the store behaves as it would
/// against a backend that confirms instantly.
///
/// `@MainActor` because the seam is `Sendable` and this class holds mutable state. The listener
/// callback is main-actor isolated too, so `publish()` calls it directly.
@MainActor
final class UITestFavoriteService: FavoriteServicing {
    private var favoritesByID: [String: Question]
    private var onChange: (@MainActor @Sendable (Result<[Question], Error>) -> Void)?

    init(favorites: [Question] = []) {
        favoritesByID = Dictionary(uniqueKeysWithValues: favorites.map { ($0.id, $0) })
    }

    func favoritesListener(
        userId: String,
        onChange: @escaping @MainActor @Sendable (Result<[Question], Error>) -> Void
    ) -> FavoriteListenerHandle {
        self.onChange = onChange
        publish()
        return UITestFavoriteListenerHandle()
    }

    func toggle(questionId: String, userId: String, currentState: Bool?) async throws -> Bool {
        let isFavorite = favoritesByID[questionId] == nil
        if isFavorite {
            favoritesByID[questionId] = Question(id: questionId, text: "", category: "")
        } else {
            favoritesByID.removeValue(forKey: questionId)
        }
        publish()
        return isFavorite
    }

    func addFavorites(questionIds: [String]) async throws -> Set<String> {
        for questionId in questionIds where favoritesByID[questionId] == nil {
            favoritesByID[questionId] = Question(id: questionId, text: "", category: "")
        }
        publish()
        return []
    }

    private func publish() {
        onChange?(.success(Array(favoritesByID.values)))
    }
}

private struct UITestFavoriteListenerHandle: FavoriteListenerHandle {
    func cancel() {}
}
#endif
