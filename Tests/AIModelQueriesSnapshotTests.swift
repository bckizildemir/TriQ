import FirebaseFirestore
import Foundation
import Testing
@testable import TTB

/// The path a live `aiQueries` snapshot takes from the listener closure to `AIModel`: map the
/// documents, then hop to the main actor. Tested here on its own, without Firebase.
@Suite(.timeLimit(.minutes(1)))
struct AIModelQueriesSnapshotTests {
    private static func queryData(question: String) -> [String: Any] {
        [
            "question": question,
            "responses": ["One", "Two", "Three"],
            "timestamp": Timestamp(date: Date(timeIntervalSince1970: 1_700_000_000)),
            "category": AICategory.other.rawValue,
            "isSaved": false,
            "isLoading": false,
        ]
    }

    private static let syncError = NSError(
        domain: "test",
        code: 1,
        userInfo: [NSLocalizedDescriptionKey: "sync-boom"]
    )

    @Test func validDocumentsAreLoadedAndInvalidOnesDropped() throws {
        let update = AIModel.queriesUpdate(
            documents: [
                (id: "a1", data: Self.queryData(question: "First?")),
                (id: "broken", data: ["question": "No other fields"]),
            ],
            error: nil
        )

        guard case .loaded(let queries) = try #require(update) else {
            Issue.record("expected .loaded, got \(String(describing: update))")
            return
        }
        #expect(queries.map(\.id) == ["a1"])
    }

    @Test func emptyDocumentsLoadAnEmptyHistory() throws {
        let update = AIModel.queriesUpdate(documents: [], error: nil)

        guard case .loaded(let queries) = try #require(update) else {
            Issue.record("expected .loaded, got \(String(describing: update))")
            return
        }
        #expect(queries.isEmpty)
    }

    @Test func aMissingSnapshotChangesNothing() {
        #expect(AIModel.queriesUpdate(documents: nil, error: nil) == nil)
    }

    @Test func anErrorBecomesASyncFailureMessage() throws {
        let update = AIModel.queriesUpdate(documents: nil, error: Self.syncError)

        guard case .syncFailed(let message) = try #require(update) else {
            Issue.record("expected .syncFailed, got \(String(describing: update))")
            return
        }
        #expect(message.contains("sync-boom"))
    }

    @Test func anErrorWinsOverDocuments() throws {
        let update = AIModel.queriesUpdate(
            documents: [(id: "a1", data: Self.queryData(question: "First?"))],
            error: Self.syncError
        )

        guard case .syncFailed = try #require(update) else {
            Issue.record("expected .syncFailed, got \(String(describing: update))")
            return
        }
    }

    @Test func aDeliveredUpdateRunsOnTheMainActor() async {
        let isLoaded: Bool = await withCheckedContinuation { continuation in
            AIModel.deliverQueriesSnapshot(
                documents: [(id: "a1", data: Self.queryData(question: "First?"))],
                error: nil
            ) { update in
                MainActor.assertIsolated()
                if case .loaded = update {
                    continuation.resume(returning: true)
                } else {
                    continuation.resume(returning: false)
                }
            }
        }

        #expect(isLoaded)
    }

    @Test func aDeliveredErrorRunsOnTheMainActor() async {
        let message: String? = await withCheckedContinuation { continuation in
            AIModel.deliverQueriesSnapshot(documents: nil, error: Self.syncError) { update in
                MainActor.assertIsolated()
                if case .syncFailed(let message) = update {
                    continuation.resume(returning: message)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }

        #expect(message?.contains("sync-boom") == true)
    }
}
