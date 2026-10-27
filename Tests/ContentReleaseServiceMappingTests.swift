import FirebaseFirestore
import FirebaseFunctions
import Foundation
import Testing
@testable import TTB

/// The logic `ContentReleaseService` and `CategoryService` keep beside their Firebase calls:
/// the snapshot listener mapping, the callable payload reads and the callable error mapping.
/// Tested without Firebase.
struct ContentReleaseServiceMappingTests {
    // MARK: Release listener

    @Test func releaseDocumentsAreMappedWithTheirIds() throws {
        var result: Result<[ContentRelease], Error>?
        ContentReleaseService.deliverSnapshot(
            documents: [
                (id: "r1", data: ["status": "published", "categoryIds": ["c1"]]),
                (id: "r2", data: ["status": "draft"]),
            ],
            error: nil
        ) { result = $0 }

        let releases = try #require(result).get()
        #expect(releases.map(\.id) == ["r1", "r2"])
        #expect(releases.first?.status == .published)
        #expect(releases.first?.categoryIds == ["c1"])
        #expect(releases.last?.status == .draft)
    }

    @Test func aMissingReleaseSnapshotIsNoReleases() throws {
        var result: Result<[ContentRelease], Error>?
        ContentReleaseService.deliverSnapshot(documents: nil, error: nil) { result = $0 }

        #expect(try #require(result).get().isEmpty)
    }

    @Test func aReleaseListenerErrorIsAFailure() {
        var result: Result<[ContentRelease], Error>?
        ContentReleaseService.deliverSnapshot(documents: [], error: URLError(.timedOut)) { result = $0 }

        guard case .failure(let error)? = result, error is URLError else {
            Issue.record("expected the URLError, got \(String(describing: result))")
            return
        }
    }

    // MARK: Category listener

    @Test func categoryDocumentsAreMappedWithTheirIds() throws {
        var result: Result<[TTB.Category], Error>?
        CategoryService.deliverSnapshot(
            documents: [
                (id: "food", data: ["sortOrder": 2, "isActive": false]),
                (id: "travel", data: [:]),
            ],
            error: nil
        ) { result = $0 }

        let categories = try #require(result).get()
        #expect(categories.map(\.id) == ["food", "travel"])
        #expect(categories.first?.sortOrder == 2)
        #expect(categories.first?.isActive == false)
        #expect(categories.last?.isActive == true)
    }

    @Test func aMissingCategorySnapshotIsNoCategories() throws {
        var result: Result<[TTB.Category], Error>?
        CategoryService.deliverSnapshot(documents: nil, error: nil) { result = $0 }

        #expect(try #require(result).get().isEmpty)
    }

    @Test func aCategoryListenerErrorIsAFailure() {
        var result: Result<[TTB.Category], Error>?
        CategoryService.deliverSnapshot(documents: [], error: URLError(.notConnectedToInternet)) { result = $0 }

        guard case .failure(let error)? = result, error is URLError else {
            Issue.record("expected the URLError, got \(String(describing: result))")
            return
        }
    }

    // MARK: Callable payloads

    @Test func publishPayloadIsRead() {
        let result = ContentReleaseService.publishResult(from: ["releaseId": "r1", "didPublish": true])

        #expect(result.releaseID == "r1")
        #expect(result.didPublish)
    }

    @Test func aPublishPayloadThatIsNotADictionaryIsNoPublish() {
        let result = ContentReleaseService.publishResult(from: "oops")

        #expect(result.releaseID == nil)
        #expect(!result.didPublish)
    }

    @Test func publishPayloadFieldsOfTheWrongTypeAreIgnored() {
        let result = ContentReleaseService.publishResult(from: ["releaseId": 5, "didPublish": "yes"])

        #expect(result.releaseID == nil)
        #expect(!result.didPublish)
    }

    @Test func notificationCountsAreRead() {
        let result = ContentReleaseService.notificationSendResult(from: [
            "attemptedCount": 4,
            "successCount": NSNumber(value: 3),
            "failureCount": 1,
            "prunedCount": "two",
        ])

        #expect(result == ContentReleaseNotificationSendResult(
            attemptedCount: 4,
            successCount: 3,
            failureCount: 1,
            prunedCount: 0
        ))
    }

    @Test func aNotificationPayloadThatIsNotADictionaryIsEmpty() {
        #expect(ContentReleaseService.notificationSendResult(from: 42) == .empty)
    }

    // MARK: Callable errors

    private static func functionsError(_ code: FunctionsErrorCode) -> NSError {
        NSError(domain: FunctionsErrorDomain, code: code.rawValue)
    }

    @Test func functionsErrorCodesMapToPublishErrors() {
        let cases: [(FunctionsErrorCode, String)] = [
            (.unauthenticated, "authenticationRequired"),
            (.permissionDenied, "adminRequired"),
            (.failedPrecondition, "missingFirestoreIndex"),
            (.unavailable, "firebaseUnavailable"),
            (.deadlineExceeded, "publishTimedOut"),
            (.invalidArgument, "invalidPublishPayload"),
            (.internal, "publishFailed"),
            (.notFound, "unknown"),
        ]

        for (code, expected) in cases {
            let mapped = ContentReleaseService.mapPublishError(Self.functionsError(code))
            #expect(Self.name(of: mapped) == expected, "code \(code.rawValue)")
        }
    }

    @Test func anErrorOutsideTheFunctionsDomainIsUnknown() {
        let mapped = ContentReleaseService.mapPublishError(URLError(.timedOut))

        guard case ContentReleaseServiceError.unknown(let inner) = mapped, inner is URLError else {
            Issue.record("expected .unknown(URLError), got \(mapped)")
            return
        }
    }

    private static func name(of error: Error) -> String {
        guard let error = error as? ContentReleaseServiceError else { return "other" }
        switch error {
        case .authenticationRequired: return "authenticationRequired"
        case .adminRequired: return "adminRequired"
        case .missingFirestoreIndex: return "missingFirestoreIndex"
        case .firebaseUnavailable: return "firebaseUnavailable"
        case .publishTimedOut: return "publishTimedOut"
        case .publishFailed: return "publishFailed"
        case .invalidPublishPayload: return "invalidPublishPayload"
        case .unknown: return "unknown"
        }
    }
}
