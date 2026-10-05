import Foundation

#if DEBUG
/// Puts a harness's guest favorite store at a known count before the harness builds it.
///
/// `GuestFavoriteModel` reads its ids in `init`, so this has to run first. Synthetic ids are
/// enough: the model counts ids, and an id that resolves to no question drops out of the rendered
/// list because `FavoriteStore` resolves guest ids through the harness corpus.
///
/// Without this the favorite-limit sheet is unreachable from a UI test. The cap is ten and the
/// largest harness fixture holds three questions, so tapping cannot get there.
///
/// Main-actor isolated as a whole because its key comes from `GuestFavoriteModel`, which is.
@MainActor
enum UITestGuestFavoriteSeed {
    /// The model's own key, not a second copy of the literal. A rename there would otherwise leave
    /// this writing where nothing reads, and the harness would start with no favorites at all.
    static let favoritesKey = GuestFavoriteModel.defaultFavoritesKey

    /// Seeds the requested count, or clears the key when no seed was asked for — every harness
    /// used to clear it unconditionally, and a harness that starts with somebody else's favorites
    /// is a flaky harness.
    static func apply(to storage: UserDefaults) {
        guard UITestLaunchOptions.shouldSeedGuestFavoritesOneBelowCap else {
            storage.removeObject(forKey: favoritesKey)
            return
        }

        storage.set(oneBelowCapIDs, forKey: favoritesKey)
    }

    /// Derived from the cap rather than written out, so raising the cap cannot leave this stale.
    private static var oneBelowCapIDs: [String] {
        (1..<GuestFavoriteModel.maxGuestFavorites).map { "ui-test-seeded-guest-favorite-\($0)" }
    }
}
#endif
