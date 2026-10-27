import Foundation

/// The shape every Firebase listener adapter repeats: log an error, map the documents with
/// `compactMap`, then hand the result to the store on the main actor.
///
/// A live adapter's snapshot closure forwards raw values here (or to a thin wrapper that does), so a
/// test can run the path a live snapshot takes without Firebase.
enum SnapshotDelivery {
    /// Maps one snapshot callback to a result and delivers it on the main actor.
    ///
    /// - Parameters:
    ///   - documents: The snapshot's documents as plain values. `nil` is a missing snapshot and
    ///     delivers an empty success.
    ///   - error: The listener error. It wins over `documents`.
    ///   - onError: Called with the raw listener error before it is mapped, for logging.
    ///   - mapError: Turns the listener error into the failure the store sees.
    ///   - decode: Decodes one document. Return `nil` to drop an invalid document.
    ///   - completion: Runs on the main actor with the result.
    static func deliver<Document, Element: Sendable>(
        documents: [Document]?,
        error: Error?,
        onError: (Error) -> Void = { _ in },
        mapError: (Error) -> Error = { $0 },
        decode: (Document) -> Element?,
        to completion: @escaping @MainActor @Sendable (Result<[Element], Error>) -> Void
    ) {
        let result: Result<[Element], Error>
        if let error {
            onError(error)
            result = .failure(mapError(error))
        } else {
            result = .success((documents ?? []).compactMap(decode))
        }

        Task { @MainActor in completion(result) }
    }
}
