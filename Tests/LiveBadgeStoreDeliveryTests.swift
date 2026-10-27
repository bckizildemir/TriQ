import Foundation
import Testing
@testable import TTB

/// The logic `LiveBadgeStore` keeps beside its Firebase closures: the user-document listener
/// mapping and the transaction block's error reporting. Tested without Firebase.
struct LiveBadgeStoreDeliveryTests {
    private struct UpdateFailure: Error {}

    private final class FixtureTransaction: BadgeUserTransaction {
        private(set) var updates: [[String: Any]] = []

        func userDocumentData() throws -> [String: Any]? { ["answerCount": 1] }

        func updateUserDocument(_ data: [String: Any]) {
            updates.append(data)
        }
    }

    // MARK: Listener

    @Test func documentDataIsDeliveredAsSuccess() throws {
        var result: Result<[String: Any]?, Error>?
        LiveBadgeStore.deliverUserSnapshot(data: ["answerCount": 3], error: nil) { result = $0 }

        let data = try #require(result).get()
        #expect(data?["answerCount"] as? Int == 3)
    }

    @Test func aMissingDocumentIsDeliveredAsSuccessWithNoData() throws {
        var result: Result<[String: Any]?, Error>?
        LiveBadgeStore.deliverUserSnapshot(data: nil, error: nil) { result = $0 }

        #expect(try #require(result).get() == nil)
    }

    @Test func anErrorIsDeliveredAsFailure() {
        var result: Result<[String: Any]?, Error>?
        LiveBadgeStore.deliverUserSnapshot(data: ["answerCount": 3], error: URLError(.timedOut)) { result = $0 }

        guard case .failure(let error)? = result, error is URLError else {
            Issue.record("expected the URLError, got \(String(describing: result))")
            return
        }
    }

    // MARK: Transaction block

    @Test func aSuccessfulPassReturnsTheUpdatesValueAndLeavesTheErrorPointerAlone() {
        let context = FixtureTransaction()
        var error: NSError?

        let value = LiveBadgeStore.runUpdates(
            { transaction in
                transaction.updateUserDocument(["streak": 2])
                return "done"
            },
            in: context,
            errorPointer: &error
        )

        #expect(value as? String == "done")
        #expect(error == nil)
        #expect(context.updates.count == 1)
    }

    @Test func aThrownErrorGoesToTheErrorPointerAndReturnsNil() {
        var error: NSError?

        let value = LiveBadgeStore.runUpdates(
            { _ in throw UpdateFailure() },
            in: FixtureTransaction(),
            errorPointer: &error
        )

        #expect(value == nil)
        #expect(error != nil)
    }

    @Test func aThrownErrorWithNoErrorPointerStillReturnsNil() {
        let value = LiveBadgeStore.runUpdates(
            { _ in throw UpdateFailure() },
            in: FixtureTransaction(),
            errorPointer: nil
        )

        #expect(value == nil)
    }
}
