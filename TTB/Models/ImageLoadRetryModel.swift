import Foundation
import Observation

/// How many times, and how patiently, a remote image is retried before the user is told it failed.
///
/// The Pexels thumbnails load from the device straight to `images.pexels.com`. On a network that
/// resets that connection every request fails at once, so an immediate retry would fail the same
/// way: each retry waits longer than the one before.
struct ImageLoadRetryPolicy: Equatable, Sendable {
    /// Wait before automatic retry number 1, 2, … Its length is the number of automatic retries.
    let retryDelays: [Duration]

    /// Three tries in all: the first load, then a retry after 1 s and another after 3 s.
    static let standard = ImageLoadRetryPolicy(retryDelays: [.seconds(1), .seconds(3)])

    /// The wait before the next automatic retry, given how many loads have failed so far
    /// (1 after the first failure). `nil` once the retries are used up.
    func delay(afterFailureNumber failureNumber: Int) -> Duration? {
        guard failureNumber >= 1, failureNumber <= retryDelays.count else { return nil }
        return retryDelays[failureNumber - 1]
    }
}

/// What makes one `LazyImage` a different load from the last: another URL, or another attempt.
struct AnswerImageLoadIdentity: Hashable {
    let url: URL
    let attempt: Int
}

/// What a remote answer image shows, decided from what has loaded so far.
enum AnswerImageSource: Equatable {
    /// The copy from the network, which always wins.
    case remote
    /// The image the device already had when the user saved, shown until `remote` is ready.
    case placeholder
    case loading
    case failed

    /// A placeholder beats a spinner and an error: it is the whole point of showing the picked
    /// image at once, and a failed download must not replace a picture the user can already see.
    static func resolve(
        hasRemoteImage: Bool,
        hasPlaceholder: Bool,
        retryStatus: ImageLoadRetryModel.Status
    ) -> AnswerImageSource {
        if hasRemoteImage { return .remote }
        if hasPlaceholder { return .placeholder }
        return retryStatus == .failed ? .failed : .loading
    }
}

/// The retry state of one remote image: reload with a growing delay, then give up and offer a button.
///
/// The view reloads by giving `LazyImage` a new `.id(attempt)`; this model only counts and waits.
@MainActor
@Observable
final class ImageLoadRetryModel {
    enum Status: Equatable {
        /// Loading, or about to be reloaded.
        case loading
        /// Retries are used up. The view shows its error state.
        case failed
    }

    private(set) var status: Status = .loading

    /// Changes each time the image should be fetched again.
    private(set) var attempt = 0

    private var failureCount = 0
    /// The newest failure already counted. A view that appears again re-runs its `.task` for a
    /// failure it has already handled; that must not count a second time.
    private var handledFailureToken = 0
    private let policy: ImageLoadRetryPolicy
    private let sleep: @Sendable (Duration) async throws -> Void

    init(
        policy: ImageLoadRetryPolicy = .standard,
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.policy = policy
        self.sleep = sleep
    }

    /// A load failed; `token` numbers the failure (the view bumps it once per failed load). Waits out
    /// the backoff and asks for a reload, or settles on `.failed`. A token that was already handled is
    /// ignored.
    ///
    /// Cancelling the calling task (the view went away) abandons the retry and un-counts the failure,
    /// so the view handles it once when it comes back.
    func loadFailed(token: Int) async {
        guard token > handledFailureToken else { return }
        let previousToken = handledFailureToken
        handledFailureToken = token
        failureCount += 1

        guard let delay = policy.delay(afterFailureNumber: failureCount) else {
            status = .failed
            return
        }

        do {
            try await sleep(delay)
        } catch {
            failureCount -= 1
            handledFailureToken = previousToken
            return
        }
        attempt += 1
    }

    func loadSucceeded() {
        failureCount = 0
        status = .loading
    }

    /// The user's button: a full set of automatic retries again.
    func retryNow() {
        failureCount = 0
        status = .loading
        attempt += 1
    }

    /// The image the view shows changed, so what happened to the old one no longer counts.
    func reset() {
        failureCount = 0
        status = .loading
    }
}
