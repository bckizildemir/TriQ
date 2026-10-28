import Foundation
import Testing
@testable import TTB

/// The shared log / compactMap / main-actor hop that every listener adapter delivers through.
@Suite(.timeLimit(.minutes(1)))
struct SnapshotDeliveryTests {
    private struct Wrapped: Error {
        let inner: Error
    }

    /// The hooks run synchronously on the caller's thread, so no lock is needed.
    private final class Recorder {
        private(set) var values: [String] = []

        func record(_ value: String) {
            values.append(value)
        }
    }

    private static func deliver(
        documents: [Int]?,
        error: Error?,
        onError: (Error) -> Void = { _ in },
        mapError: (Error) -> Error = { $0 }
    ) async -> Result<[String], Error> {
        await withCheckedContinuation { continuation in
            SnapshotDelivery.deliver(
                documents: documents,
                error: error,
                onError: onError,
                mapError: mapError,
                decode: { $0 > 0 ? "doc\($0)" : nil }
            ) { result in
                MainActor.assertIsolated()
                continuation.resume(returning: result)
            }
        }
    }

    @Test func decodedDocumentsAreDeliveredAndInvalidOnesDropped() async throws {
        let result = await Self.deliver(documents: [1, 0, 2], error: nil)

        #expect(try result.get() == ["doc1", "doc2"])
    }

    @Test func aMissingSnapshotIsAnEmptySuccess() async throws {
        let result = await Self.deliver(documents: nil, error: nil)

        #expect(try result.get().isEmpty)
    }

    @Test func anErrorIsAFailureAndWinsOverDocuments() async {
        let result = await Self.deliver(documents: [1], error: URLError(.timedOut))

        guard case .failure(let error) = result, error is URLError else {
            Issue.record("expected the URLError, got \(result)")
            return
        }
    }

    @Test func theErrorIsMappedAfterTheLogCallSeesTheRawOne() async {
        let recorder = Recorder()
        let result = await Self.deliver(
            documents: nil,
            error: URLError(.timedOut),
            onError: { error in recorder.record(error is URLError ? "raw" : "mapped") },
            mapError: { Wrapped(inner: $0) }
        )

        #expect(recorder.values == ["raw"])
        guard case .failure(let error) = result, error is Wrapped else {
            Issue.record("expected the mapped error, got \(result)")
            return
        }
    }

    @Test func noErrorNeverCallsTheLogHook() async {
        let recorder = Recorder()
        _ = await Self.deliver(documents: [1], error: nil, onError: { _ in recorder.record("called") })

        #expect(recorder.values.isEmpty)
    }
}
