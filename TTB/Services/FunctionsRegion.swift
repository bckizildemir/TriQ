import FirebaseFunctions

extension Functions {
    /// The Functions client for the region that hosts every TTB callable.
    ///
    /// Every service gets its Firebase objects one way: fetch them inside the method that uses
    /// them — `Firestore.firestore()`, `Functions.europeWest1`, `Storage.storage()` — and never keep
    /// one in a stored, lazy, or forwarding computed property. A method that uses Firestore more
    /// than once may bind it to one local `let db`. The SDK returns its cached instance on each
    /// call. None of these types is `Sendable`, so a stored copy would pin an actor's region
    /// (TriQ#12, TriQ#74).
    static var europeWest1: Functions {
        functions(region: "europe-west1")
    }
}
