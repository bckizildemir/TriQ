import FirebaseFirestore

/// A live listener registration `BadgeModel` can cancel, without naming `ListenerRegistration`.
protocol BadgeUserListening {
    func remove()
}

/// One read/update pass over a user's badge document inside `BadgeStoring.runUserTransaction`.
///
/// Mirrors Firestore's own `Transaction.getDocument`/`updateData`, so a fixture can stand in
/// without a `Transaction` of its own to construct.
protocol BadgeUserTransaction {
    func userDocumentData() throws -> [String: Any]?
    func updateUserDocument(_ data: [String: Any])
}

/// `BadgeModel`'s Firestore surface, as a seam.
///
/// The six operations FIX-6 named: read the user document, write it, list badge definitions, run
/// a transaction against the user document (`checkBadgeProgress` and
/// `incrementAnswerCountIfNeeded` each run one), and observe the user document. `BadgeModel` keeps
/// every bit of badge business logic — progress math, streak calculation, unlock detection — and
/// this seam carries only the network calls, so a fixture never has to reimplement that logic to
/// stand in for Firestore.
protocol BadgeStoring: Sendable {
    func getUserDocument(userId: String) async throws -> (exists: Bool, data: [String: Any])
    func setUserDocument(userId: String, data: sending [String: Any], merge: Bool) async throws
    func getBadgeDefinitionDocuments() async throws -> [(id: String, data: [String: Any])]
    func runUserTransaction(
        userId: String,
        _ updates: @escaping @Sendable (BadgeUserTransaction) throws -> Any?
    ) async throws -> Any?
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

    func runUserTransaction(
        userId: String,
        _ updates: @escaping @Sendable (BadgeUserTransaction) throws -> Any?
    ) async throws -> Any? {
        let db = Firestore.firestore()
        let userRef = db.collection("users").document(userId)
        return try await db.runTransaction { transaction, errorPointer -> Any? in
            let context = FirestoreBadgeUserTransaction(transaction: transaction, userRef: userRef)
            return Self.runUpdates(updates, in: context, errorPointer: errorPointer)
        }
    }

    /// Runs one transaction pass. A thrown error goes to `errorPointer` as an `NSError` and the
    /// pass returns `nil`, which is how Firestore's transaction block reports a failure.
    ///
    /// Kept out of the Firebase closure so a test can run it with a fixture transaction.
    static func runUpdates(
        _ updates: @Sendable (BadgeUserTransaction) throws -> Any?,
        in context: BadgeUserTransaction,
        errorPointer: NSErrorPointer
    ) -> Any? {
        do {
            return try updates(context)
        } catch {
            errorPointer?.pointee = error as NSError
            return nil
        }
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

private struct FirestoreBadgeUserTransaction: BadgeUserTransaction {
    let transaction: Transaction
    let userRef: DocumentReference

    func userDocumentData() throws -> [String: Any]? {
        try transaction.getDocument(userRef).data()
    }

    func updateUserDocument(_ data: [String: Any]) {
        transaction.updateData(data, forDocument: userRef)
    }
}

private struct FirestoreBadgeUserListening: BadgeUserListening {
    let registration: ListenerRegistration

    func remove() {
        registration.remove()
    }
}
