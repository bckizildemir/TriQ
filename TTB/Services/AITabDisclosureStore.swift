import Foundation

struct AITabDisclosureStore {
    private let userDefaults: UserDefaults
    private let storageKey: String

    init(
        userDefaults: UserDefaults = .standard,
        version: Int = AppConfig.aiTabDisclosureVersion
    ) {
        self.userDefaults = userDefaults
        storageKey = "aiTabDisclosure.seen.v\(version)"
    }

    var hasSeenCurrentVersion: Bool {
        userDefaults.bool(forKey: storageKey)
    }

    func markSeen() {
        userDefaults.set(true, forKey: storageKey)
    }
}
