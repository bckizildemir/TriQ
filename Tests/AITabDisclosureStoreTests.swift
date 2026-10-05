import Foundation
import XCTest
@testable import TTB

final class AITabDisclosureStoreTests: XCTestCase {
    func testDisclosureDefaultsToNotSeen() {
        let (defaults, suiteName) = makeUserDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = AITabDisclosureStore(userDefaults: defaults, version: 1)

        XCTAssertFalse(store.hasSeenCurrentVersion)
    }

    func testMarkSeenPersistsCurrentVersion() {
        let (defaults, suiteName) = makeUserDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = AITabDisclosureStore(userDefaults: defaults, version: 1)
        store.markSeen()

        XCTAssertTrue(store.hasSeenCurrentVersion)
    }

    func testNewVersionRequiresDisclosureAgain() {
        let (defaults, suiteName) = makeUserDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let firstVersionStore = AITabDisclosureStore(userDefaults: defaults, version: 1)
        firstVersionStore.markSeen()

        let secondVersionStore = AITabDisclosureStore(userDefaults: defaults, version: 2)

        XCTAssertFalse(secondVersionStore.hasSeenCurrentVersion)
    }

    private func makeUserDefaults() -> (UserDefaults, String) {
        let suiteName = "AITabDisclosureStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return (defaults, suiteName)
    }
}
