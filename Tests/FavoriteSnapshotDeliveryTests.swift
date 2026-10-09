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

    @Test func aSignedInUserIdAttachesTheListener() {
        let accepted = FavoriteService.acceptsListener(for: "user-1") { result in
            Issue.record("a valid userId must not report a result, got \(result)")
        }

        #expect(accepted)
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
