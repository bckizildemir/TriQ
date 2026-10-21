import Foundation
import Testing
@testable import TTB

/// The call site of the empty-`userId` guard (TriQ#54). `FavoriteSnapshotDeliveryTests` tests the
/// guard function alone; these tests build a real `FavoriteService` and call the methods that must
/// use it. If the guard call is removed, or `Firestore.firestore()` moves above it, the empty
/// `userId` reaches Firebase: these tests then fail or crash, because no Firebase app is
/// configured in the test host.
@Suite(.timeLimit(.minutes(1)))
struct FavoriteListenerCallSiteTests {
    @Test func anEmptyUserIdReturnsNoRegistrationAndReportsInvalidUserId() async {
        let service = FavoriteService()

        let result: Result<[Question], Error> = await withCheckedContinuation { continuation in
            Task {
                let registration = await service.setupFavoritesListener(userId: "") { result in
                    MainActor.assertIsolated()
                    continuation.resume(returning: result)
                }
                #expect(registration == nil)
            }
        }

        guard case .failure(let error) = result,
              case .invalidUserId? = error as? FavoriteService.FavoriteError
        else {
            Issue.record("expected FavoriteError.invalidUserId, got \(result)")
            return
        }
    }

    @Test func anEmptyUserIdGivesAHandleWhoseCancelDoesNothing() async {
        let service = FavoriteService()

        await confirmation("the completion reports once", expectedCount: 1) { reported in
            await withCheckedContinuation { done in
                Task {
                    let handle = await service.favoritesListener(userId: "") { _ in
                        reported()
                        done.resume()
                    }
                    handle.cancel()
                    handle.cancel()
                }
            }
        }
    }
}
