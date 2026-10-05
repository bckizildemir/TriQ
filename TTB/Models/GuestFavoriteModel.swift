import Foundation

enum GuestFavoriteToggleResult: Equatable {
    case added(count: Int)
    case removed(count: Int)
    case limitReached(count: Int)
    case unchanged(count: Int)
}

/// One-shot signal that a guest crossed the favorite milestone. The host observes it,
/// shows a toast, and clears it — the identity makes repeat milestones distinguishable
/// even when `count` and `limit` are unchanged.
struct GuestFavoriteMilestone: Identifiable, Equatable {
    let id = UUID()
    let count: Int
    let limit: Int
}

@MainActor
final class GuestFavoriteModel: ObservableObject {
    static let maxGuestFavorites = 10
    static let favoriteMilestoneThreshold = 3

    @Published private(set) var guestFavorites: [String]
    @Published private(set) var pendingFavoriteMilestone: GuestFavoriteMilestone?
    @Published var shouldShowGuestUpgrade = false
    @Published var migrationSuccessMessage: String?

    private let storage: UserDefaults
    private let favoritesKey: String
    // Delivery is marked at emit time, not at dismissal: the milestone now rides a
    // fire-and-forget toast, so there is no "still on screen" state to track.
    private var deliveredMilestoneThisSession = false

    /// Where guest favorites are held on the device.
    ///
    /// Named rather than written out twice: `UITestGuestFavoriteSeed` writes this same key before a
    /// harness builds the model, and a renamed literal would leave the seed writing to a key nobody
    /// reads — a harness that silently starts with no favorites.
    static let defaultFavoritesKey = "guest.favorite.questionIds"

    init(
        storage: UserDefaults = .standard,
        favoritesKey: String = GuestFavoriteModel.defaultFavoritesKey
    ) {
        self.storage = storage
        self.favoritesKey = favoritesKey
        let storedFavorites = storage.stringArray(forKey: favoritesKey) ?? []
        let normalizedFavorites = Self.normalizedFavorites(storedFavorites)
        self.guestFavorites = normalizedFavorites
        if normalizedFavorites != storedFavorites {
            storage.set(normalizedFavorites, forKey: favoritesKey)
        }
    }

    func canAddFavorite() -> Bool {
        guestFavorites.count < Self.maxGuestFavorites
    }

    @discardableResult
    func toggleFavorite(questionId: String) -> GuestFavoriteToggleResult {
        if isFavorite(questionId: questionId) {
            removeFavorite(questionId: questionId)
            return .removed(count: guestFavorites.count)
        }

        return addFavorite(questionId: questionId)
    }

    @discardableResult
    func addFavorite(questionId: String) -> GuestFavoriteToggleResult {
        let normalizedQuestionId = Self.normalizedQuestionID(questionId)
        guard !normalizedQuestionId.isEmpty else {
            return .unchanged(count: guestFavorites.count)
        }

        guard !guestFavorites.contains(normalizedQuestionId) else {
            return .unchanged(count: guestFavorites.count)
        }

        guard canAddFavorite() else {
            return .limitReached(count: guestFavorites.count)
        }

        guestFavorites.append(normalizedQuestionId)
        persistFavorites()

        if guestFavorites.count == Self.favoriteMilestoneThreshold, !deliveredMilestoneThisSession {
            deliveredMilestoneThisSession = true
            pendingFavoriteMilestone = GuestFavoriteMilestone(
                count: guestFavorites.count,
                limit: Self.maxGuestFavorites
            )
        }

        return .added(count: guestFavorites.count)
    }

    func removeFavorite(questionId: String) {
        let normalizedQuestionId = Self.normalizedQuestionID(questionId)
        let previousCount = guestFavorites.count
        guestFavorites.removeAll { $0 == normalizedQuestionId }

        if previousCount >= Self.favoriteMilestoneThreshold,
           guestFavorites.count < Self.favoriteMilestoneThreshold {
            deliveredMilestoneThisSession = false
            pendingFavoriteMilestone = nil
        }

        persistFavorites()
    }

    func isFavorite(questionId: String) -> Bool {
        guestFavorites.contains(Self.normalizedQuestionID(questionId))
    }

    func getFavoriteCount() -> Int {
        guestFavorites.count
    }

    /// Called by the host once the milestone toast has been handed to the toast center.
    func clearPendingFavoriteMilestone() {
        pendingFavoriteMilestone = nil
    }

    func requestGuestUpgrade() {
        shouldShowGuestUpgrade = true
    }

    /// The local half of migration, for when the write is somebody else's job: clears the
    /// device-held ids the account actually accepted, and raises the success message the host
    /// shows. Called by `FavoriteStore` once the backend has responded.
    ///
    /// An id in `unavailableQuestionIds` stays on the device and is retried on the next migration
    /// attempt, so a partial migration loses nothing — the same guarantee `clearGuestFavorites()`
    /// gives a fully-successful one.
    func completeMigration(unavailableQuestionIds: Set<String>) {
        guestFavorites.removeAll { !unavailableQuestionIds.contains($0) }
        persistFavorites()
        deliveredMilestoneThisSession = false
        pendingFavoriteMilestone = nil
        shouldShowGuestUpgrade = false
        migrationSuccessMessage = String(localized: "guest.favorite.migration.success")
    }

    func clearGuestFavorites() {
        guestFavorites = []
        deliveredMilestoneThisSession = false
        pendingFavoriteMilestone = nil
        persistFavorites()
    }

    func clearMigrationSuccessMessage() {
        migrationSuccessMessage = nil
    }

    private func persistFavorites() {
        storage.set(guestFavorites, forKey: favoritesKey)
    }

    private static func normalizedFavorites(_ favorites: [String]) -> [String] {
        var seen = Set<String>()
        var normalized: [String] = []

        for favorite in favorites {
            let questionId = normalizedQuestionID(favorite)
            guard !questionId.isEmpty, seen.insert(questionId).inserted else { continue }
            normalized.append(questionId)
            if normalized.count == maxGuestFavorites { break }
        }

        return normalized
    }

    private static func normalizedQuestionID(_ questionId: String) -> String {
        questionId.trimmingCharacters(in: .whitespacesAndNewlines)
    }

}
