import XCTest
@testable import TTB

/// The favorite toggle's UI consequences live on `ToastCenter`, the single owner: an account-write
/// failure raises an error toast, and the guest cap raises the signup prompt. Both ride the outcome
/// `FavoriteStore.toggle` returns — nothing observes a flag the guest store publishes on the side.
@MainActor
final class ToastCenterFavoriteTests: XCTestCase {

    func testReachingTheGuestCapRaisesTheLimitPrompt() async {
        let (toastCenter, store) = await makeGuestSetup()

        for index in 0..<(GuestFavoriteModel.maxGuestFavorites - 1) {
            await toastCenter.toggleFavorite(question("q\(index)"), using: store)
            XCTAssertFalse(toastCenter.isGuestFavoriteLimitPromptPresented)
        }

        // The add that lands on the cap raises the prompt.
        await toastCenter.toggleFavorite(question("last-allowed"), using: store)
        XCTAssertTrue(toastCenter.isGuestFavoriteLimitPromptPresented)
    }

    func testAToggleBlockedByTheCapKeepsThePromptRaised() async {
        let (toastCenter, store) = await makeGuestSetup()
        for index in 0..<GuestFavoriteModel.maxGuestFavorites {
            await toastCenter.toggleFavorite(question("q\(index)"), using: store)
        }
        toastCenter.isGuestFavoriteLimitPromptPresented = false

        await toastCenter.toggleFavorite(question("one-too-many"), using: store)

        XCTAssertTrue(toastCenter.isGuestFavoriteLimitPromptPresented)
    }

    func testAnAddBelowTheCapDoesNotRaiseThePrompt() async {
        let (toastCenter, store) = await makeGuestSetup()

        await toastCenter.toggleFavorite(question("q1"), using: store)

        XCTAssertFalse(toastCenter.isGuestFavoriteLimitPromptPresented)
        XCTAssertNil(toastCenter.currentToast)
    }

    // MARK: - Helpers

    private func makeGuestSetup() async -> (ToastCenter, FavoriteStore) {
        let guest = GuestFavoriteModel(
            storage: UserDefaults(suiteName: "ToastCenterFavoriteTests.\(UUID().uuidString)")!
        )
        let store = FavoriteStore(
            service: FakeFavoriteService(),
            guestFavorites: guest,
            resolveQuestions: { _ in [] }
        )
        await store.setIdentity(.guest)
        return (ToastCenter(), store)
    }

    private func question(_ id: String) -> Question {
        Question(
            id: id,
            text: "Question \(id)?",
            category: "Daily",
            isFavorite: false,
            createdAt: Date(timeIntervalSince1970: 0)
        )
    }
}
