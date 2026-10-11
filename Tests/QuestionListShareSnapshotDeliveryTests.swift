import Foundation
import Testing
@testable import TTB

/// The path a live Firestore snapshot takes from the listener closure to `SharedQuestionListStore`:
/// map the documents, then hop to the main actor. The fakes skip this path, so it is tested here
/// on its own, without Firebase.
@Suite(.timeLimit(.minutes(1)))
struct QuestionListShareSnapshotDeliveryTests {
    @Test func ownedDocumentsReachTheCallbackAsShares() async throws {
        let result: Result<[QuestionListShare], Error> = await withCheckedContinuation { continuation in
            QuestionListShareService.deliverOwnedShares(
                documents: [
                    (id: "s1", data: ["ownerId": "owner"]),
                    (id: "broken", data: [:]),
                ],
                error: nil
            ) { result in
                MainActor.assertIsolated()
                continuation.resume(returning: result)
            }
        }

        #expect(try result.get().map(\.id) == ["s1"])
    }

    @Test func aMissingOwnedSnapshotReachesTheCallbackAsNoShares() async throws {
        let result: Result<[QuestionListShare], Error> = await withCheckedContinuation { continuation in
            QuestionListShareService.deliverOwnedShares(documents: nil, error: nil) {
                continuation.resume(returning: $0)
            }
        }

        #expect(try result.get().isEmpty)
    }

    @Test func anOwnedListenerErrorReachesTheCallbackAsAFailure() async {
        let result: Result<[QuestionListShare], Error> = await withCheckedContinuation { continuation in
            QuestionListShareService.deliverOwnedShares(
                documents: nil,
                error: URLError(.notConnectedToInternet)
            ) {
                continuation.resume(returning: $0)
            }
        }

        guard case .failure(let error) = result, error is URLError else {
            Issue.record("expected the URLError, got \(result)")
            return
        }
    }

    @Test func recipientDocumentsWithAParentShareReachTheCallback() async throws {
        let result: Result<[QuestionListShareRecipient], Error> = await withCheckedContinuation { continuation in
            QuestionListShareService.deliverAcceptedRecipients(
                documents: [
                    (id: "r1", shareId: "s1", data: ["recipientId": "r1", "status": "accepted"]),
                    (id: "orphan", shareId: nil, data: ["recipientId": "orphan"]),
                ],
                error: nil
            ) { result in
                MainActor.assertIsolated()
                continuation.resume(returning: result)
            }
        }

        let recipients = try result.get()
        #expect(recipients.map(\.recipientId) == ["r1"])
        #expect(recipients.map(\.shareId) == ["s1"])
    }

    @Test func aRecipientListenerErrorReachesTheCallbackAsAFailure() async {
        let result: Result<[QuestionListShareRecipient], Error> = await withCheckedContinuation { continuation in
            QuestionListShareService.deliverAcceptedRecipients(
                documents: nil,
                error: URLError(.timedOut)
            ) {
                continuation.resume(returning: $0)
            }
        }

        guard case .failure(let error) = result, error is URLError else {
            Issue.record("expected the URLError, got \(result)")
            return
        }
    }
}
