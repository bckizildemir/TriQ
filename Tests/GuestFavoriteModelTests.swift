import XCTest
@testable import TTB

@MainActor
final class GuestFavoriteModelTests: XCTestCase {
    private var suiteName: String!
    private var storage: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "GuestFavoriteModelTests.\(UUID().uuidString)"
        storage = UserDefaults(suiteName: suiteName)
        storage.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        storage.removePersistentDomain(forName: suiteName)
        storage = nil
        suiteName = nil
        super.tearDown()
    }

    func testAddRemoveAndFavoriteLookup() {
        let model = makeModel()

        XCTAssertEqual(model.addFavorite(questionId: "q1"), .added(count: 1))
        XCTAssertTrue(model.isFavorite(questionId: "q1"))
        XCTAssertEqual(model.guestFavorites, ["q1"])

        model.removeFavorite(questionId: "q1")

        XCTAssertFalse(model.isFavorite(questionId: "q1"))
        XCTAssertEqual(model.guestFavorites, [])
    }

    func testRejectsDuplicateFavorites() {
        let model = makeModel()

        XCTAssertEqual(model.addFavorite(questionId: " q1 "), .added(count: 1))
        XCTAssertEqual(model.addFavorite(questionId: "q1"), .unchanged(count: 1))
        XCTAssertEqual(model.addFavorite(questionId: " \n "), .unchanged(count: 1))

        XCTAssertEqual(model.guestFavorites, ["q1"])
    }

    func testLookupAndToggleNormalizeQuestionID() {
        let model = makeModel()
        _ = model.addFavorite(questionId: "q1")

        XCTAssertTrue(model.isFavorite(questionId: " q1 "))
        XCTAssertEqual(
            model.toggleFavorite(questionId: "\nq1\t"),
            .removed(count: 0)
        )
        XCTAssertTrue(model.guestFavorites.isEmpty)
    }

    func testCapsFavoritesAtTenAndReportsTheLimit() {
        let model = makeModel()

        for index in 1...9 {
            XCTAssertEqual(model.addFavorite(questionId: "q\(index)"), .added(count: index))
        }

        // The add that reaches the cap still succeeds; the next one is blocked. The store maps
        // both counts onto the outcome that raises the signup prompt — this model no longer owns
        // that presentation flag.
        XCTAssertEqual(model.addFavorite(questionId: "q10"), .added(count: 10))
        XCTAssertEqual(model.addFavorite(questionId: "q11"), .limitReached(count: 10))
        XCTAssertEqual(model.guestFavorites.count, 10)
        XCTAssertFalse(model.isFavorite(questionId: "q11"))
    }

    func testMilestoneFiresOnlyAtThirdFavorite() {
        let model = makeModel()

        _ = model.addFavorite(questionId: "q1")
        XCTAssertNil(model.pendingFavoriteMilestone)

        _ = model.addFavorite(questionId: "q2")
        XCTAssertNil(model.pendingFavoriteMilestone)

        _ = model.addFavorite(questionId: "q3")
        XCTAssertEqual(model.pendingFavoriteMilestone?.count, 3)
        XCTAssertEqual(model.pendingFavoriteMilestone?.limit, GuestFavoriteModel.maxGuestFavorites)

        model.clearPendingFavoriteMilestone()
        XCTAssertNil(model.pendingFavoriteMilestone)

        _ = model.addFavorite(questionId: "q4")
        XCTAssertNil(model.pendingFavoriteMilestone)
    }

    /// Delivery is marked when the milestone is emitted, not when the host consumes it —
    /// so a host that never clears it still only ever sees one milestone per session.
    func testMilestoneIsNotReemittedWhenHostNeverClearsIt() {
        let model = makeModel()

        _ = model.addFavorite(questionId: "q1")
        _ = model.addFavorite(questionId: "q2")
        _ = model.addFavorite(questionId: "q3")
        let firstMilestone = model.pendingFavoriteMilestone
        XCTAssertNotNil(firstMilestone)

        _ = model.addFavorite(questionId: "q4")
        _ = model.addFavorite(questionId: "q5")

        XCTAssertEqual(model.pendingFavoriteMilestone?.id, firstMilestone?.id)
    }

    func testMilestoneCanFireAgainAfterDroppingBelowThresholdViaRemove() {
        let model = makeModel()

        _ = model.addFavorite(questionId: "q1")
        _ = model.addFavorite(questionId: "q2")
        _ = model.addFavorite(questionId: "q3")
        model.clearPendingFavoriteMilestone()

        model.removeFavorite(questionId: "q1")
        XCTAssertEqual(model.getFavoriteCount(), 2)
        XCTAssertNil(model.pendingFavoriteMilestone)

        _ = model.addFavorite(questionId: "q4")
        XCTAssertEqual(model.pendingFavoriteMilestone?.count, 3)
    }

    func testMilestoneCanFireAgainAfterClearGuestFavorites() {
        let model = makeModel()

        _ = model.addFavorite(questionId: "q1")
        _ = model.addFavorite(questionId: "q2")
        _ = model.addFavorite(questionId: "q3")
        model.clearPendingFavoriteMilestone()
        model.clearGuestFavorites()

        _ = model.addFavorite(questionId: "q4")
        _ = model.addFavorite(questionId: "q5")
        XCTAssertNil(model.pendingFavoriteMilestone)

        _ = model.addFavorite(questionId: "q6")
        XCTAssertEqual(model.pendingFavoriteMilestone?.count, 3)
    }

    /// Dropping below the threshold clears an undelivered milestone too, so a guest who
    /// immediately un-favorites doesn't get a toast about a count they no longer have.
    func testRemovingBelowThresholdClearsPendingMilestone() {
        let model = makeModel()

        _ = model.addFavorite(questionId: "q1")
        _ = model.addFavorite(questionId: "q2")
        _ = model.addFavorite(questionId: "q3")
        XCTAssertNotNil(model.pendingFavoriteMilestone)

        model.removeFavorite(questionId: "q3")

        XCTAssertNil(model.pendingFavoriteMilestone)
    }

    func testPersistsFavoritesAcrossModelReinitialization() {
        let firstModel = makeModel()
        _ = firstModel.addFavorite(questionId: "q1")
        _ = firstModel.addFavorite(questionId: "q2")

        let secondModel = makeModel()

        XCTAssertEqual(secondModel.guestFavorites, ["q1", "q2"])
    }

    func testInitializationNormalizesAndCapsCorruptedPersistedFavorites() {
        storage.set(
            [" q1 ", "", "q1", " q2", "q3 ", "q4", "q5", "q6", "q7", "q8", "q9", "q10", "q11"],
            forKey: "guest.favorite.questionIds.test"
        )

        let model = makeModel()

        XCTAssertEqual(
            model.guestFavorites,
            ["q1", "q2", "q3", "q4", "q5", "q6", "q7", "q8", "q9", "q10"]
        )
        XCTAssertEqual(
            storage.stringArray(forKey: "guest.favorite.questionIds.test"),
            model.guestFavorites
        )
        XCTAssertFalse(model.canAddFavorite())
    }

    /// The write half of migration moved to `FavoriteStore`, which owns the backend call and
    /// clears these ids only once it succeeds — see `FavoriteStoreTests`. What stays here is the
    /// local half.
    func testCompleteMigrationClearsFavoritesAndRaisesTheSuccessMessage() {
        let model = makeModel()
        _ = model.addFavorite(questionId: "q1")
        _ = model.addFavorite(questionId: "q2")

        model.completeMigration(unavailableQuestionIds: [])

        XCTAssertEqual(model.guestFavorites, [])
        XCTAssertEqual(storage.stringArray(forKey: "guest.favorite.questionIds.test"), [])
        XCTAssertNotNil(model.migrationSuccessMessage)
        XCTAssertNil(model.pendingFavoriteMilestone)
    }

    /// The bug this guards against: a partially-successful migration must not silently drop the
    /// ids the server could not accept. See the Guest Favorite entry in `CONTEXT.md`.
    func testCompleteMigrationRetainsIdsTheServerReportedUnavailable() {
        let model = makeModel()
        _ = model.addFavorite(questionId: "q1")
        _ = model.addFavorite(questionId: "q2")
        _ = model.addFavorite(questionId: "q3")

        model.completeMigration(unavailableQuestionIds: ["q2"])

        XCTAssertEqual(model.guestFavorites, ["q2"])
        XCTAssertEqual(storage.stringArray(forKey: "guest.favorite.questionIds.test"), ["q2"])
        XCTAssertNotNil(model.migrationSuccessMessage)
    }

    private func makeModel() -> GuestFavoriteModel {
        GuestFavoriteModel(
            storage: storage,
            favoritesKey: "guest.favorite.questionIds.test"
        )
    }
}
