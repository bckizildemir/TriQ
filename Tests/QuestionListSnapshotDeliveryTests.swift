import Foundation
import os
import Testing
@testable import TTB

/// The path a live Firestore snapshot takes from the `QuestionListService` listener closure to
/// `QuestionListStore`: map the documents, then hop to the main actor. `MockQuestionListService`
/// skips this path, so it is tested here on its own, without Firebase.
struct QuestionListSnapshotDeliveryTests {
    @Test(.timeLimit(.minutes(1)))
    func documentsReachTheCallbackAsLists() async throws {
        let result = await deliver(
            documents: [
                (id: "list-1", data: ["ownerId": "user-1", "name": "Road trip"]),
                (id: "broken", data: ["ownerId": "user-1"]),
            ],
            error: nil
        )

        #expect(try result.get().map(\.id) == ["list-1"])
    }

    @Test(.timeLimit(.minutes(1)))
    func aMissingSnapshotReachesTheCallbackAsNoLists() async throws {
        let result = await deliver(documents: nil, error: nil)

        #expect(try result.get().isEmpty)
    }

    @Test(.timeLimit(.minutes(1)))
    func aListenerErrorReachesTheCallbackAsAFailure() async {
        let result = await deliver(documents: nil, error: URLError(.notConnectedToInternet))

        guard case .failure(let error) = result else {
            Issue.record("expected a failure, got \(result)")
            return
        }
        #expect((error as? URLError)?.code == .notConnectedToInternet)
    }

    private func deliver(
        documents: [(id: String, data: [String: Any])]?,
        error: Error?
    ) async -> Result<[QuestionList], Error> {
        await withCheckedContinuation { continuation in
            QuestionListService.deliverSnapshot(
                documents: documents,
                error: error,
                logger: Logger(subsystem: "TTBTests", category: "QuestionListSnapshotDeliveryTests")
            ) { result in
                MainActor.assertIsolated()
                continuation.resume(returning: result)
            }
        }
    }
}
