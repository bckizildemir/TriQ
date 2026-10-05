import Foundation

#if DEBUG
extension UserDefaults {
    /// A `UserDefaults` suite scoped to one harness, isolated from the app's real defaults and from
    /// every other harness's fixtures. Falls back to `.standard` on the rare failure to create a
    /// named suite, same as every harness root did inline before this.
    static func harnessSuite(named name: String) -> UserDefaults {
        UserDefaults(suiteName: name) ?? .standard
    }
}
#endif
