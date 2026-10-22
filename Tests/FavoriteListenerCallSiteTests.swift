import FirebaseFirestore
import Foundation
import Testing
@testable import TTB

/// The call site of the empty-`userId` guard (TriQ#54). `FavoriteSnapshotDeliveryTests` tests the
/// guard function alone; these tests build a real `FavoriteService` and call the methods that must
/// use it. The test host (TTB.app) configures Firebase, so a regressed guard would read live
/// Firestore. The service gets a Firestore provider that records an issue instead: if the guard
/// call is removed, or the provider call moves above it, the test fails before any Firebase use.
@Suite(.timeLimit(.minutes(1)))
struct FavoriteListenerCallSiteTests {
    /// A provider that must never run. It records the failure, then stops: it has no `Firestore`
    /// to return, and fetching a real one would touch Firebase.
    private static let unreachableFirestore: @Sendable () -> Firestore = {
        Issue.record("the Firestore provider ran for an empty userId")
        fatalError("the Firestore provider ran for an empty userId")
    }

    @Test func anEmptyUserIdReturnsNoRegistrationAndReportsInvalidUserId() async {
        let service = FavoriteService(firestore: Self.unreachableFirestore)
        let (results, continuation) = AsyncStream<Result<[Question], Error>>.makeStream()

        let registration = await service.setupFavoritesListener(userId: "") { result in
            MainActor.assertIsolated()
            continuation.yield(result)
        }
        #expect(registration == nil)

        var iterator = results.makeAsyncIterator()
        let result = await iterator.next()
        guard case .failure(let error)? = result,
              case .invalidUserId? = error as? FavoriteService.FavoriteError
        else {
            Issue.record("expected FavoriteError.invalidUserId, got \(String(describing: result))")
            return
        }
    }

    @Test func anEmptyUserIdGivesAHandleWhoseCancelDoesNothing() async {
        let service = FavoriteService(firestore: Self.unreachableFirestore)
        let (reports, continuation) = AsyncStream<Void>.makeStream()

        let handle = await service.favoritesListener(userId: "") { _ in
            continuation.yield()
        }
        handle.cancel()
        handle.cancel()

        var iterator = reports.makeAsyncIterator()
        await iterator.next()
        continuation.finish()
        #expect(await iterator.next() == nil, "the completion reports once")
    }
}
