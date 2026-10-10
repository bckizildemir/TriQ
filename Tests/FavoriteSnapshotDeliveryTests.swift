import Foundation
import Testing
@testable import TTB

/// The path a live Firestore snapshot takes from the listener closure to `FavoriteStore`: map the
/// documents, then hop to the main actor. `FakeFavoriteService` skips this path, so it is tested
/// here on its own, without Firebase.
@Suite(.timeLimit(.minutes(1)))
struct FavoriteSnapshotDeliveryTests {
    @Test func documentsReachTheCallbackAsQuestions() async throws {
        let result = await deliver(
            documents: [
                (id: "q1", data: ["text": "First?", "category": "life"]),
                (id: "broken", data: ["text": "No category"]),
            ],
            error: nil
        )

        let questions = try result.get()
        #expect(questions.map(\.id) == ["q1"])
    }

    @Test func aMissingSnapshotReachesTheCallbackAsNoFavorites() async throws {
        let result = await deliver(documents: nil, error: nil)

        #expect(try result.get().isEmpty)
    }

    @Test func aListenerErrorReachesTheCallbackAsAFailure() async {
        let result = await deliver(documents: nil, error: URLError(.notConnectedToInternet))

        guard case .failure(let error) = result,
              case .unknown? = error as? FavoriteService.FavoriteError
        else {
            Issue.record("expected FavoriteError.unknown, got \(result)")
            return
        }
    }

    @Test func anEmptyUserIdAttachesNoListenerAndReportsInvalidUserId() async {
        let result: Result<[Question], Error> = await withCheckedContinuation { continuation in
            let accepted = FavoriteService.acceptsListener(for: "") { result in
                MainActor.assertIsolated()
                continuation.resume(returning: result)
            }
            #expect(!accepted)
        }

        guard case .failure(let error) = result,
              case .invalidUserId? = error as? FavoriteService.FavoriteError
        else {
            Issue.record("expected FavoriteError.invalidUserId, got \(result)")
            return
        }
    }

    /// A rejection is reported from a `Task { @MainActor }`, so the test cannot simply return: a
    /// stray report would run after it. It waits on a barrier instead — a rejected call made after
    /// the accepted one. `Task` enqueues an isolated closure on its actor when it is created
    /// (SE-0431), and the main actor runs jobs of one priority in order, so by the time the
    /// barrier's report arrives, any report from the accepted call has already run.
    @Test func aSignedInUserIdIsAcceptedWithoutAReport() async {
        await confirmation("a valid userId reports a result", expectedCount: 0) { reported in
            let accepted = FavoriteService.acceptsListener(for: "user-1") { _ in reported() }
            #expect(accepted)

            await withCheckedContinuation { barrier in
                _ = FavoriteService.acceptsListener(for: "") { _ in barrier.resume() }
            }
        }
    }

    private func deliver(
        documents: [(id: String, data: [String: Any])]?,
        error: Error?
    ) async -> Result<[Question], Error> {
        await withCheckedContinuation { continuation in
            FavoriteService.deliverSnapshot(documents: documents, error: error) { result in
                MainActor.assertIsolated()
                continuation.resume(returning: result)
            }
        }
    }
}
