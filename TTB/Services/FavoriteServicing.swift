import Foundation

/// Cancels a favorites subscription.
///
/// Exists so the seam never names a Firebase type: the live adapter wraps a
/// `ListenerRegistration`, and a test adapter returns something that does nothing.
///
/// `Sendable` because the live adapter is an actor and hands the handle back to the main-actor
/// store. `cancel()` is synchronous and safe to call more than once.
protocol FavoriteListenerHandle: Sendable {
    func cancel()
}

/// Everything `FavoriteStore` needs from the backend to own favorite state.
///
/// Two adapters satisfy this: `FavoriteService` in the app, and an in-memory fake in the tests.
/// The fake is the point — it is what lets the store's precedence ladder, its optimistic
/// rollback, and its reconciliation against a snapshot be exercised without Firebase, and
/// without the `service == nil` local-mode branch that the models grew instead.
protocol FavoriteServicing: Sendable {
    /// Streams the questions the user has favorited, re-emitting on every change.
    ///
    /// Membership in the snapshot is the truth. The `isFavorite` flag carried by these
    /// questions is not read — it is decoded from ambient auth state and says nothing the
    /// snapshot has not already said.
    ///
    /// `onChange` runs on the main actor: its one consumer is `FavoriteStore`, so the adapter
    /// makes the hop once and the store applies each snapshot synchronously.
    func favoritesListener(
        userId: String,
        onChange: @escaping @MainActor @Sendable (Result<[Question], Error>) -> Void
    ) async -> FavoriteListenerHandle

    /// Flips one question's favorite state and returns the state the server settled on, which
    /// is authoritative: the caller's optimistic guess is reconciled against it.
    ///
    /// `currentState` is the caller's view of the state before the flip, used only to resolve a
    /// response payload that omits the new value.
    func toggle(questionId: String, userId: String, currentState: Bool?) async throws -> Bool

    /// Adds the signed-in user to each question's favorites, idempotently. Returns the ids the
    /// server could not add — their question was missing or is no longer approved — so the
    /// caller can retain exactly those instead of losing them.
    ///
    /// Used when guest favorites migrate onto a permanent account. A question the user already
    /// favorited is left alone, so a retried migration is harmless — which matters because the
    /// caller retries on every foreground until it succeeds.
    func addFavorites(questionIds: [String]) async throws -> Set<String>
}
