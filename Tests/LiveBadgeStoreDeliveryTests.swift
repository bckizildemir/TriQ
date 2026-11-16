import Foundation
import Testing
@testable import TTB

/// The logic `LiveBadgeStore` keeps beside its Firebase closure: the user-document listener
/// mapping. Tested without Firebase.
struct LiveBadgeStoreDeliveryTests {
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
}
