import XCTest
@testable import TTB

/// Every rule the three view-local resolvers and two override engines used to encode, asserted
/// through the one interface that replaces them. None of this needed Firebase before; none of it
/// was reachable either.
@MainActor
final class FavoriteStoreTests: XCTestCase {

    // MARK: - The precedence ladder

    func testAccountStateFallsBackToTheQuestionSeedBeforeAnySnapshot() async {
        let (store, _, _) = makeStore()
        await store.setIdentity(.account(userId: "user-1"))

        XCTAssertTrue(store.state(of: question("q1", isFavorite: true)))
        XCTAssertFalse(store.state(of: question("q2", isFavorite: false)))
    }

    func testSnapshotMembershipOverridesTheQuestionSeed() async {
        let (store, service, _) = makeStore()
        await store.setIdentity(.account(userId: "user-1"))

        service.emit([question("q2")])

        // The seed said q1 was a favorite and q2 was not; the snapshot disagrees and wins.
        XCTAssertFalse(store.state(of: question("q1", isFavorite: true)))
        XCTAssertTrue(store.state(of: question("q2", isFavorite: false)))
    }

    func testPendingWriteOverridesTheSnapshot() async {
        let (store, service, _) = makeStore()
        await store.setIdentity(.account(userId: "user-1"))
        let favorited = question("q1")
        service.emit([favorited])

        let outcome = await store.toggle(favorited)

        XCTAssertEqual(outcome, .removed)
        XCTAssertFalse(store.state(of: favorited))
        XCTAssertTrue(store.favorites.isEmpty)
    }

    // MARK: - Optimism, reconciliation, rollback

    func testToggleAddsOptimisticallyAndPublishesTheQuestion() async {
        let (store, service, _) = makeStore()
        await store.setIdentity(.account(userId: "user-1"))
        service.emit([])
        let target = question("q1")

        let outcome = await store.toggle(target)

        XCTAssertEqual(outcome, .added)
        XCTAssertTrue(store.state(of: target))
        XCTAssertEqual(store.favorites.map(\.id), ["q1"])
        XCTAssertEqual(service.toggleCalls.map(\.questionId), ["q1"])
        XCTAssertEqual(service.toggleCalls.first?.currentState, false)
    }

    func testSnapshotConfirmingAPendingWriteClearsIt() async {
        let (store, service, _) = makeStore()
        await store.setIdentity(.account(userId: "user-1"))
        service.emit([])
        let target = question("q1")
        await store.toggle(target)

        service.emit([target])

        // Still a favorite, now because the backend says so rather than because of the override.
        XCTAssertTrue(store.state(of: target))
        // A stale seed must not resurface once the override is gone.
        XCTAssertTrue(store.state(of: question("q1", isFavorite: false)))
        XCTAssertEqual(store.favorites.map(\.id), ["q1"])
    }

    func testBackendSettlingOnTheOppositeStateCorrectsTheOptimisticGuess() async {
        let (store, service, _) = makeStore()
        await store.setIdentity(.account(userId: "user-1"))
        service.emit([])
        service.toggleResult = .success(false)
        let target = question("q1")

        let outcome = await store.toggle(target)

        XCTAssertEqual(outcome, .removed)
        XCTAssertFalse(store.state(of: target))
        XCTAssertTrue(store.favorites.isEmpty)
    }

    func testFailedToggleRollsBackAndReportsTheError() async {
        let (store, service, _) = makeStore()
        await store.setIdentity(.account(userId: "user-1"))
        let existing = question("q1")
        service.emit([existing])
        service.toggleResult = .failure(FakeFavoriteServiceError.unavailable)

        let outcome = await store.toggle(existing)

        XCTAssertEqual(outcome, .failed)
        XCTAssertTrue(store.state(of: existing), "the optimistic removal should be rolled back")
        XCTAssertEqual(store.favorites.map(\.id), ["q1"])
        XCTAssertEqual(store.error, FakeFavoriteServiceError.unavailable.localizedDescription)
    }

    func testSnapshotFailureIsReportedWithoutDroppingKnownFavorites() async {
        let (store, service, _) = makeStore()
        await store.setIdentity(.account(userId: "user-1"))
        service.emit([question("q1")])

        service.emitFailure(FakeFavoriteServiceError.unavailable)

        XCTAssertEqual(store.error, FakeFavoriteServiceError.unavailable.localizedDescription)
        XCTAssertEqual(store.favorites.map(\.id), ["q1"])
    }

    // MARK: - Ordering

    func testAccountFavoritesAreNewestFirst() async {
        let (store, service, _) = makeStore()
        await store.setIdentity(.account(userId: "user-1"))

        service.emit([
            question("older", createdAt: Date(timeIntervalSince1970: 100)),
            question("newest", createdAt: Date(timeIntervalSince1970: 300)),
            question("middle", createdAt: Date(timeIntervalSince1970: 200)),
        ])

        XCTAssertEqual(store.favorites.map(\.id), ["newest", "middle", "older"])
    }

    func testGuestFavoritesKeepTheOrderTheyWereSavedIn() async {
        let corpus = [question("q3"), question("q1"), question("q2")]
        let (store, _, guest) = makeStore(corpus: corpus)
        await store.setIdentity(.guest)

        await store.toggle(question("q2"))
        await store.toggle(question("q3"))
        await store.toggle(question("q1"))

        XCTAssertEqual(guest.guestFavorites, ["q2", "q3", "q1"])
        XCTAssertEqual(store.favorites.map(\.id), ["q2", "q3", "q1"])
    }

    // MARK: - Guest rules

    func testGuestStateAndToggleComeFromTheGuestStore() async {
        let (store, service, guest) = makeStore(corpus: [question("q1")])
        await store.setIdentity(.guest)
        let target = question("q1")

        XCTAssertFalse(store.state(of: target))

        let addOutcome = await store.toggle(target)
        XCTAssertEqual(addOutcome, .added)
        XCTAssertTrue(store.state(of: target))
        XCTAssertEqual(guest.guestFavorites, ["q1"])

        let removeOutcome = await store.toggle(target)
        XCTAssertEqual(removeOutcome, .removed)
        XCTAssertFalse(store.state(of: target))
        XCTAssertTrue(store.favorites.isEmpty)
        XCTAssertTrue(service.toggleCalls.isEmpty, "a guest favorite must not reach the backend")
    }

    func testGuestAddLandingOnTheCapReportsItWasSavedAtTheLimit() async {
        let (store, _, guest) = makeStore()
        await store.setIdentity(.guest)

        var lastOutcome: FavoriteToggleOutcome?
        for index in 0..<GuestFavoriteModel.maxGuestFavorites {
            lastOutcome = await store.toggle(question("q\(index)"))
        }

        // The add that reaches the cap both saves the favorite and signals the cap, so a single
        // returned outcome is enough to raise the signup prompt — no second source of truth.
        XCTAssertEqual(lastOutcome, .guestLimitReached)
        XCTAssertEqual(guest.guestFavorites.count, GuestFavoriteModel.maxGuestFavorites)
    }

    func testGuestToggleBlockedByTheCapReportsTheLimitAndSavesNothing() async {
        let (store, _, guest) = makeStore()
        await store.setIdentity(.guest)
        for index in 0..<GuestFavoriteModel.maxGuestFavorites {
            await store.toggle(question("q\(index)"))
        }

        let outcome = await store.toggle(question("one-too-many"))

        XCTAssertEqual(outcome, .guestLimitReached)
        XCTAssertEqual(guest.guestFavorites.count, GuestFavoriteModel.maxGuestFavorites)
        XCTAssertFalse(guest.guestFavorites.contains("one-too-many"))
    }

    func testGuestSeedIsIgnored() async {
        let (store, _, _) = makeStore()
        await store.setIdentity(.guest)

        // A question decoded while somebody else was signed in must not read as this guest's.
        XCTAssertFalse(store.state(of: question("q1", isFavorite: true)))
    }

    // MARK: - Signed out

    func testSignedOutFallsBackToTheSeedAndRefusesWrites() async {
        let (store, service, _) = makeStore()

        XCTAssertTrue(store.state(of: question("q1", isFavorite: true)))

        let outcome = await store.toggle(question("q1"))
        XCTAssertEqual(outcome, .failed)
        XCTAssertEqual(store.error, FavoriteStoreError.notSignedIn.localizedDescription)
        XCTAssertTrue(store.favorites.isEmpty)
        XCTAssertTrue(service.toggleCalls.isEmpty)
    }

    // MARK: - Identity changes

    func testChangingIdentityCancelsTheListenerAndDropsPendingState() async {
        let (store, service, _) = makeStore()
        await store.setIdentity(.account(userId: "user-1"))
        service.emit([])
        let target = question("q1")
        await store.toggle(target)
        XCTAssertTrue(store.state(of: target))

        await store.setIdentity(.account(userId: "user-2"))

        XCTAssertEqual(service.handles.count, 2)
        XCTAssertTrue(service.handles[0].isCancelled, "the previous user's listener must be removed")
        XCTAssertFalse(service.handles[1].isCancelled)
        XCTAssertEqual(service.listenerUserIDs, ["user-1", "user-2"])
        XCTAssertTrue(store.favorites.isEmpty)
        // The pending write belonged to user-1, so its state must not survive the switch.
        XCTAssertFalse(store.state(of: question("q1", isFavorite: false)))
    }

    func testSnapshotFromAPreviousUserIsIgnored() async {
        let (store, service, _) = makeStore()
        await store.setIdentity(.account(userId: "user-1"))
        let previousUserListener = service.currentListener()
        await store.setIdentity(.account(userId: "user-2"))

        previousUserListener(.success([question("leaked")]))

        XCTAssertTrue(store.favorites.isEmpty)
        XCTAssertFalse(store.state(of: question("leaked", isFavorite: false)))
    }

    // MARK: - Migration

    func testMigrationSendsGuestIDsAndClearsThemOnSuccess() async {
        let (store, service, guest) = makeStore(corpus: [question("q1"), question("q2")])
        await store.setIdentity(.guest)
        await store.toggle(question("q1"))
        await store.toggle(question("q2"))

        await store.migrateGuestFavorites(to: "user-1")

        XCTAssertEqual(service.addFavoritesCalls, [["q1", "q2"]])
        XCTAssertTrue(guest.guestFavorites.isEmpty)
        XCTAssertNotNil(guest.migrationSuccessMessage)
    }

    /// The data-loss bug this guards against: a migration the server only partly accepts must not
    /// clear ids it never confirmed. See the Guest Favorite entry in `CONTEXT.md`.
    func testMigrationRetainsOnlyTheIdsTheServerReportedUnavailable() async {
        let (store, service, guest) = makeStore(corpus: [question("q1"), question("q2"), question("q3")])
        await store.setIdentity(.guest)
        await store.toggle(question("q1"))
        await store.toggle(question("q2"))
        await store.toggle(question("q3"))
        service.addFavoritesUnavailableIDs = ["q2"]

        await store.migrateGuestFavorites(to: "user-1")

        XCTAssertEqual(guest.guestFavorites, ["q2"])
        XCTAssertNotNil(guest.migrationSuccessMessage)
    }

    func testFailedMigrationKeepsGuestFavoritesForARetry() async {
        let (store, service, guest) = makeStore(corpus: [question("q1")])
        await store.setIdentity(.guest)
        await store.toggle(question("q1"))
        service.addFavoritesError = FakeFavoriteServiceError.unavailable

        await store.migrateGuestFavorites(to: "user-1")

        XCTAssertEqual(guest.guestFavorites, ["q1"])
        XCTAssertNil(guest.migrationSuccessMessage)

        // The retry succeeds and is the same call, because the write is idempotent.
        service.addFavoritesError = nil
        await store.migrateGuestFavorites(to: "user-1")
        XCTAssertEqual(service.addFavoritesCalls, [["q1"], ["q1"]])
        XCTAssertTrue(guest.guestFavorites.isEmpty)
    }

    func testMigrationWithNothingToMoveDoesNotCallTheBackend() async {
        let (store, service, _) = makeStore()
        await store.setIdentity(.guest)

        await store.migrateGuestFavorites(to: "user-1")
        await store.migrateGuestFavorites(to: "")

        XCTAssertTrue(service.addFavoritesCalls.isEmpty)
    }

    // MARK: - Helpers

    private func makeStore(
        corpus: [Question] = []
    ) -> (FavoriteStore, FakeFavoriteService, GuestFavoriteModel) {
        let service = FakeFavoriteService()
        let guest = GuestFavoriteModel(
            storage: UserDefaults(suiteName: "FavoriteStoreTests.\(UUID().uuidString)")!
        )
        let questionsByID = Dictionary(uniqueKeysWithValues: corpus.map { ($0.id, $0) })
        let store = FavoriteStore(
            service: service,
            guestFavorites: guest,
            resolveQuestions: { ids in ids.compactMap { questionsByID[$0] } }
        )
        return (store, service, guest)
    }

    private func question(
        _ id: String,
        isFavorite: Bool = false,
        createdAt: Date = Date(timeIntervalSince1970: 0)
    ) -> Question {
        Question(
            id: id,
            text: "Question \(id)?",
            category: "Daily",
            isFavorite: isFavorite,
            createdAt: createdAt
        )
    }
}
