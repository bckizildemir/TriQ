import FirebaseFunctions

extension Functions {
    /// The Functions client for the region that hosts every TTB callable.
    ///
    /// Fetch it inside the method that uses it. Do not store it. The rule and its reasons are in
    /// `docs/agents/firebase-objects.md`.
    static var europeWest1: Functions {
        functions(region: "europe-west1")
    }
}
