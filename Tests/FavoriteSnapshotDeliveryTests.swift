import Foundation
import Testing
@testable import TTB

/// The path a live Firestore snapshot takes from the listener closure to `FavoriteStore`: map the
/// documents, then hop to the main actor. `FakeFavoriteService` skips this path, so it is tested
/// here on its own, without Firebase.
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
