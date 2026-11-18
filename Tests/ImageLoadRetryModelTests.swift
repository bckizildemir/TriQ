import Synchronization
import Testing
@testable import TTB

struct ImageLoadRetryPolicyTests {
    @Test func standardPolicyRetriesTwiceWithGrowingDelay() {
        let policy = ImageLoadRetryPolicy.standard

        #expect(policy.delay(afterFailureNumber: 1) == .seconds(1))
        #expect(policy.delay(afterFailureNumber: 2) == .seconds(3))
        #expect(policy.delay(afterFailureNumber: 3) == nil)
    }

    @Test func failureNumberBelowOneHasNoDelay() {
        #expect(ImageLoadRetryPolicy.standard.delay(afterFailureNumber: 0) == nil)
    }
}

@MainActor
struct ImageLoadRetryModelTests {
    private final class SleepLog: Sendable {
        private let storage = Mutex<[Duration]>([])

        func record(_ duration: Duration) {
            storage.withLock { $0.append(duration) }
        }

        var durations: [Duration] {
            storage.withLock { $0 }
        }
    }

    private func model(log: SleepLog = SleepLog()) -> ImageLoadRetryModel {
        ImageLoadRetryModel(policy: .standard, sleep: { log.record($0) })
    }

    @Test func firstFailureWaitsThenReloads() async {
        let log = SleepLog()
        let model = model(log: log)

        await model.loadFailed()

        #expect(log.durations == [.seconds(1)])
        #expect(model.attempt == 1)
        #expect(model.status == .loading)
    }

    @Test func givesUpAfterTheLastAutomaticRetry() async {
        let log = SleepLog()
        let model = model(log: log)

        await model.loadFailed()
        await model.loadFailed()
        await model.loadFailed()

        #expect(log.durations == [.seconds(1), .seconds(3)])
        #expect(model.attempt == 2)
        #expect(model.status == .failed)
    }

    @Test func retryNowReloadsAndGrantsAFreshSetOfRetries() async {
        let model = model()
        await model.loadFailed()
        await model.loadFailed()
        await model.loadFailed()
        #expect(model.status == .failed)

        model.retryNow()
        #expect(model.status == .loading)
        #expect(model.attempt == 3)

        await model.loadFailed()
        #expect(model.status == .loading)
        #expect(model.attempt == 4)
    }

    @Test func successForgetsEarlierFailures() async {
        let model = model()
        await model.loadFailed()
        model.loadSucceeded()

        await model.loadFailed()
        await model.loadFailed()

        #expect(model.status == .loading)
    }

    @Test func cancelledWaitDoesNotReload() async {
        let model = ImageLoadRetryModel(policy: .standard, sleep: { _ in throw CancellationError() })

        await model.loadFailed()

        #expect(model.attempt == 0)
        #expect(model.status == .loading)
    }
}

struct AnswerImageSourceTests {
    @Test func networkCopyWinsOverEverything() {
        #expect(AnswerImageSource.resolve(hasRemoteImage: true, hasPlaceholder: true, retryStatus: .failed) == .remote)
    }

    @Test func placeholderCoversLoadingAndFailure() {
        #expect(AnswerImageSource.resolve(hasRemoteImage: false, hasPlaceholder: true, retryStatus: .loading) == .placeholder)
        #expect(AnswerImageSource.resolve(hasRemoteImage: false, hasPlaceholder: true, retryStatus: .failed) == .placeholder)
    }

    @Test func withoutPlaceholderFailureShowsTheErrorOnlyAfterRetriesAreUsedUp() {
        #expect(AnswerImageSource.resolve(hasRemoteImage: false, hasPlaceholder: false, retryStatus: .loading) == .loading)
        #expect(AnswerImageSource.resolve(hasRemoteImage: false, hasPlaceholder: false, retryStatus: .failed) == .failed)
    }
}
