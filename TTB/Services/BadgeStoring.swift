import FirebaseFirestore

/// A live listener registration `BadgeModel` can cancel, without naming `ListenerRegistration`.
protocol BadgeUserListening {
    func remove()
}

/// `BadgeModel`'s Firestore surface, as a seam.
///
/// Four operations: read the user document, write it, list badge definitions, and observe the user
/// document. The answer counters and badge progress are server-owned (`saveAnswer` writes them), so
/// the seam has no transaction over them: the client-side transaction that used to be here wrote
/// fields the rules refuse (#168). This seam carries only the network calls.
protocol BadgeStoring: Sendable {
    func getUserDocument(userId: String) async throws -> (exists: Bool, data: [String: Any])
    func setUserDocument(userId: String, data: sending [String: Any], merge: Bool) async throws
    func getBadgeDefinitionDocuments() async throws -> [(id: String, data: [String: Any])]
    func observeUserDocument(
        userId: String,
        onChange: @escaping (Result<[String: Any]?, Error>) -> Void
    ) -> BadgeUserListening
}

/// The production adapter: every operation goes straight to Firestore.
///
/// Holds no `Firestore` instance: Firebase does not mark it `Sendable`, so storing one would stop
/// this struct being `Sendable`. `Firestore.firestore()` returns the same cached default instance
/// on every call.
struct LiveBadgeStore: BadgeStoring {
    func getUserDocument(userId: String) async throws -> (exists: Bool, data: [String: Any]) {
        let snapshot = try await Firestore.firestore().collection("users").document(userId).getDocument()
        return (snapshot.exists, snapshot.data() ?? [:])
    }

    func setUserDocument(userId: String, data: sending [String: Any], merge: Bool) async throws {
        try await Firestore.firestore().collection("users").document(userId).setData(data, merge: merge)
    }

    func getBadgeDefinitionDocuments() async throws -> [(id: String, data: [String: Any])] {
        let snapshot = try await Firestore.firestore().collection("badges").getDocuments()
        return snapshot.documents.map { ($0.documentID, $0.data()) }
    }

    /// Maps one user-document snapshot callback to the observer's result. A missing snapshot is
    /// a success with no data.
    ///
    /// Kept out of the Firebase closure so a test can run the exact path a live snapshot takes.
    static func deliverUserSnapshot(
        data: [String: Any]?,
        error: Error?,
        to onChange: (Result<[String: Any]?, Error>) -> Void
    ) {
        if let error {
            onChange(.failure(error))
        } else {
            onChange(.success(data))
        }
    }

    func observeUserDocument(
        userId: String,
        onChange: @escaping (Result<[String: Any]?, Error>) -> Void
    ) -> BadgeUserListening {
        let registration = Firestore.firestore().collection("users").document(userId)
            .addSnapshotListener { snapshot, error in
                Self.deliverUserSnapshot(data: snapshot?.data(), error: error, to: onChange)
            }
        return FirestoreBadgeUserListening(registration: registration)
    }
}

private struct FirestoreBadgeUserListening: BadgeUserListening {
    let registration: ListenerRegistration

    func remove() {
        registration.remove()
    }
}
