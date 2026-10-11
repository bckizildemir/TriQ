import FirebaseFunctions

extension Functions {
    /// The Functions client for the region that hosts every TTB callable.
    ///
    /// A computed property on purpose: call it inside the method that needs it and do not store
    /// the result as actor state. `Functions` is not `Sendable`, so a stored copy would pin the
    /// actor's region (TriQ#12).
    static var europeWest1: Functions {
        functions(region: "europe-west1")
    }
}
