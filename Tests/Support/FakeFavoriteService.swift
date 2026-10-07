import Foundation
import Synchronization
@testable import TTB

/// Test adapter at the favorites seam.
///
/// The second adapter that makes the seam real: it holds the snapshot callback so a test can push
/// snapshots when it chooses, which is what lets the store's precedence ladder, rollback and
/// reconciliation be driven deterministically without Firebase.
final class FakeFavoriteListenerHandle: FavoriteListenerHandle {
    private let cancelled = Mutex(false)

    var isCancelled: Bool {
        cancelled.withLock { $0 }
    }

    func cancel() {
        cancelled.withLock { $0 = true }
    }
}

@MainActor
final class FakeFavoriteService: FavoriteServicing {
    /// Overrides what `toggle` returns. Left nil, it mirrors the caller's optimistic guess by
    /// flipping `currentState`, which is what the real backend does on a healthy write.
    var toggleResult: Result<Bool, Error>?
    var addFavoritesError: Error?
    /// Ids `addFavorites` reports as unavailable, mirroring what the real callable returns for a
    /// question that is missing or no longer approved. Empty means every id was accepted.
    var addFavoritesUnavailableIDs: Set<String> = []

    private(set) var toggleCalls: [(questionId: String, userId: String, currentState: Bool?)] = []
    private(set) var addFavoritesCalls: [[String]] = []
    private(set) var listenerUserIDs: [String] = []
    private(set) var handles: [FakeFavoriteListenerHandle] = []

    private var onChange: (@MainActor @Sendable (Result<[Question], Error>) -> Void)?

    func favoritesListener(
        userId: String,
        onChange: @escaping @MainActor @Sendable (Result<[Question], Error>) -> Void
    ) -> FavoriteListenerHandle {
        listenerUserIDs.append(userId)
        self.onChange = onChange
        let handle = FakeFavoriteListenerHandle()
        handles.append(handle)
        return handle
    }

    func toggle(questionId: String, userId: String, currentState: Bool?) async throws -> Bool {
        toggleCalls.append((questionId: questionId, userId: userId, currentState: currentState))
        switch toggleResult {
        case .success(let isFavorite):
            return isFavorite
        case .failure(let error):
            throw error
        case nil:
            return !(currentState ?? false)
        }
    }

    func addFavorites(questionIds: [String]) async throws -> Set<String> {
        addFavoritesCalls.append(questionIds)
        if let addFavoritesError {
            throw addFavoritesError
        }
        return addFavoritesUnavailableIDs
    }

    // MARK: - Driving the store

    /// Pushes a snapshot. The seam's callback is main-actor isolated and so is this fake, so the
    /// store has applied the snapshot by the time this returns and a test can assert on the next
    /// line.
    func emit(_ questions: [Question]) {
        onChange?(.success(questions))
    }

    func emitFailure(_ error: Error) {
        onChange?(.failure(error))
    }

    /// The callback registered by the current listener, for tests that need to fire a snapshot
    /// from a listener the store has since replaced.
    func currentListener() -> @MainActor @Sendable (Result<[Question], Error>) -> Void {
        onChange ?? { _ in }
    }
}

enum FakeFavoriteServiceError: LocalizedError {
    case unavailable

    var errorDescription: String? {
        "Favorites are unavailable."
    }
}
