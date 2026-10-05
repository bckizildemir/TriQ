import Foundation

#if DEBUG
/// A harness's `BadgeStoring`: every read comes back empty, every write is discarded, and no
/// listener ever reaches Firestore.
///
/// `observeUserDocument` still calls `onChange` once, synchronously, with no data — the same shape
/// `loadBadges()` gets when a real user document has nothing in it yet. That completes the loading
/// flow (`isLoading` goes back to `false`, `badges` fills in from the bundled definitions file)
/// instead of leaving a harness screen spinning forever.
struct NoOpBadgeStore: BadgeStoring {
    func getUserDocument(userId: String) async throws -> (exists: Bool, data: [String: Any]) {
        (false, [:])
    }

    func setUserDocument(userId: String, data: [String: Any], merge: Bool) async throws {}

    func getBadgeDefinitionDocuments() async throws -> [(id: String, data: [String: Any])] {
        []
    }

    func runUserTransaction(
        userId: String,
        _ updates: @escaping @Sendable (BadgeUserTransaction) throws -> Any?
    ) async throws -> Any? {
        try updates(NoOpBadgeUserTransaction())
    }

    func observeUserDocument(
        userId: String,
        onChange: @escaping (Result<[String: Any]?, Error>) -> Void
    ) -> BadgeUserListening {
        onChange(.success(nil))
        return NoOpBadgeUserListening()
    }
}

private struct NoOpBadgeUserTransaction: BadgeUserTransaction {
    func userDocumentData() throws -> [String: Any]? { nil }
    func updateUserDocument(_ data: [String: Any]) {}
}

private struct NoOpBadgeUserListening: BadgeUserListening {
    func remove() {}
}
#endif
