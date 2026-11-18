import Foundation
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

        await model.loadFailed(token: 1)

        #expect(log.durations == [.seconds(1)])
        #expect(model.attempt == 1)
        #expect(model.status == .loading)
    }

    @Test func givesUpAfterTheLastAutomaticRetry() async {
        let log = SleepLog()
        let model = model(log: log)

        await model.loadFailed(token: 1)
        await model.loadFailed(token: 2)
        await model.loadFailed(token: 3)

        #expect(log.durations == [.seconds(1), .seconds(3)])
        #expect(model.attempt == 2)
        #expect(model.status == .failed)
    }

    @Test func retryNowReloadsAndGrantsAFreshSetOfRetries() async {
        let model = model()
        await model.loadFailed(token: 1)
        await model.loadFailed(token: 2)
        await model.loadFailed(token: 3)
        #expect(model.status == .failed)

        model.retryNow()
        #expect(model.status == .loading)
        #expect(model.attempt == 3)

        await model.loadFailed(token: 4)
        #expect(model.status == .loading)
        #expect(model.attempt == 4)
    }

    @Test func successForgetsEarlierFailures() async {
        let model = model()
        await model.loadFailed(token: 1)
        model.loadSucceeded()

        await model.loadFailed(token: 2)
        await model.loadFailed(token: 3)

        #expect(model.status == .loading)
    }

    @Test func repeatedFailureTokenIsIgnored() async {
        let log = SleepLog()
        let model = model(log: log)

        // The view's `.task` runs again when it reappears, with the same token.
        await model.loadFailed(token: 1)
        await model.loadFailed(token: 1)
        await model.loadFailed(token: 1)

        #expect(log.durations == [.seconds(1)])
        #expect(model.attempt == 1)
        #expect(model.status == .loading)
    }

    @Test func repeatedTokenAfterGivingUpStaysFailedWithoutAnotherWait() async {
        let log = SleepLog()
        let model = model(log: log)
        await model.loadFailed(token: 1)
        await model.loadFailed(token: 2)
        await model.loadFailed(token: 3)

        await model.loadFailed(token: 3)

        #expect(log.durations.count == 2)
        #expect(model.status == .failed)
    }

    @Test func cancelledWaitDoesNotReload() async {
        let model = ImageLoadRetryModel(policy: .standard, sleep: { _ in throw CancellationError() })

        await model.loadFailed(token: 1)

        #expect(model.attempt == 0)
        #expect(model.status == .loading)
    }

    @Test func cancelledWaitIsHandledOnceWhenTheViewComesBack() async {
        let calls = Mutex(0)
        let model = ImageLoadRetryModel(policy: .standard, sleep: { _ in
            let call = calls.withLock { count -> Int in
                count += 1
                return count
            }
            if call == 1 { throw CancellationError() }
        })

        await model.loadFailed(token: 1) // the view went away mid-wait
        await model.loadFailed(token: 1) // it came back: handled once, as the first failure
        await model.loadFailed(token: 1) // and not again

        #expect(calls.withLock { $0 } == 2)
        #expect(model.attempt == 1)
        #expect(model.status == .loading)
    }
}

struct AnswerImageLoadIdentityTests {
    @Test func anotherURLIsAnotherLoad() throws {
        let first = AnswerImageLoadIdentity(url: try #require(URL(string: "https://images.pexels.com/a.jpg")), attempt: 0)
        let second = AnswerImageLoadIdentity(url: try #require(URL(string: "https://images.pexels.com/b.jpg")), attempt: 0)

        #expect(first != second)
    }

    @Test func aRetryIsAnotherLoad() throws {
        let url = try #require(URL(string: "https://images.pexels.com/a.jpg"))

        #expect(AnswerImageLoadIdentity(url: url, attempt: 0) != AnswerImageLoadIdentity(url: url, attempt: 1))
        #expect(AnswerImageLoadIdentity(url: url, attempt: 1) == AnswerImageLoadIdentity(url: url, attempt: 1))
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
