import FirebaseAuth
import FirebaseFunctions
import Foundation
import Testing
@testable import TTB

/// The `deleteOwnAccountData` error mapping and response check, which `LiveAccountDeletionOperations`
/// keeps in static functions so they run here without Firebase (TriQ#88).
struct AccountDeletionCallableMappingTests {
    private static func functionsError(_ code: FunctionsErrorCode) -> NSError {
        NSError(
            domain: FunctionsErrorDomain,
            code: code.rawValue,
            userInfo: [NSLocalizedDescriptionKey: "Raw server text."]
        )
    }

    // Raw codes, because FunctionsErrorCode is not Sendable and test arguments must be.
    @Test(arguments: [
        FunctionsErrorCode.internal.rawValue,
        FunctionsErrorCode.unavailable.rawValue,
        FunctionsErrorCode.deadlineExceeded.rawValue,
        FunctionsErrorCode.notFound.rawValue,
        FunctionsErrorCode.permissionDenied.rawValue,
    ])
    func callableFailureMapsToTheRetryMessage(code: Int) throws {
        let code = try #require(FunctionsErrorCode(rawValue: code))

        let error = LiveAccountDeletionOperations.deletionError(forCallableError: Self.functionsError(code))

        #expect(error == .dataDeletionFailed)
        #expect(error.localizedDescription == String(localized: "profile.deleteAccount.failed.message"))
        #expect(error.localizedDescription != "Raw server text.")
    }

    @Test func unauthenticatedCallableMeansTheAccountIsAlreadyDeleted() {
        let error = LiveAccountDeletionOperations.deletionError(
            forCallableError: Self.functionsError(.unauthenticated)
        )

        #expect(error == .accountAlreadyDeleted)
    }

    // After the cached token expires, the callable throws the SDK's Auth refresh error unwrapped.
    @Test(arguments: [
        AuthErrorCode.userNotFound.rawValue,
        AuthErrorCode.userTokenExpired.rawValue,
        AuthErrorCode.invalidUserToken.rawValue,
    ])
    func authRefreshErrorOutOfTheCallableMeansTheAccountIsAlreadyDeleted(code: Int) {
        let authError = NSError(domain: AuthErrorDomain, code: code)

        let error = LiveAccountDeletionOperations.deletionError(forCallableError: authError)

        #expect(error == .accountAlreadyDeleted)
    }

    @Test func otherAuthErrorOutOfTheCallableMapsToTheRetryMessage() {
        let authError = NSError(domain: AuthErrorDomain, code: AuthErrorCode.networkError.rawValue)

        let error = LiveAccountDeletionOperations.deletionError(forCallableError: authError)

        #expect(error == .dataDeletionFailed)
    }

    @Test func callableWaitsLongerThanTheServerTimeout() {
        // The server sets timeoutSeconds 300 for deleteOwnAccountData.
        #expect(LiveAccountDeletionOperations.callableTimeout > 300)
    }

    // Raw codes, because AuthErrorCode is not Sendable and test arguments must be.
    @Test(arguments: [
        AuthErrorCode.userNotFound.rawValue,
        AuthErrorCode.userTokenExpired.rawValue,
        AuthErrorCode.invalidUserToken.rawValue,
    ])
    func reauthenticationFailureForAMissingUserMeansAlreadyDeleted(code: Int) {
        let authError = NSError(domain: AuthErrorDomain, code: code)

        let mapped = LiveAccountDeletionOperations.deletionError(forReauthenticationError: authError)

        #expect(mapped as? AccountDeletionError == .accountAlreadyDeleted)
    }

    @Test func wrongPasswordReauthenticationErrorPassesThrough() {
        let authError = NSError(domain: AuthErrorDomain, code: AuthErrorCode.wrongPassword.rawValue)

        let mapped = LiveAccountDeletionOperations.deletionError(forReauthenticationError: authError)

        #expect((mapped as NSError) == authError)
    }

    @Test func nonAuthReauthenticationErrorPassesThrough() {
        let mapped = LiveAccountDeletionOperations.deletionError(
            forReauthenticationError: URLError(.notConnectedToInternet)
        )

        #expect(mapped is URLError)
    }

    @Test func differentUserStaysUnauthenticatedNotAlreadyDeleted() {
        #expect(throws: AccountDeletionError.unauthenticated) {
            try LiveAccountDeletionOperations.requireSameUser(currentUserID: "u2", expectedUserID: "u1")
        }
    }

    @Test func networkErrorMapsToTheRetryMessage() {
        let error = LiveAccountDeletionOperations.deletionError(
            forCallableError: URLError(.notConnectedToInternet)
        )

        #expect(error == .dataDeletionFailed)
    }

    @Test func successResponseReadsTheProfilePhotoURL() throws {
        let summary = try LiveAccountDeletionOperations.summary(fromCallableData: [
            "success": true,
            "profileImageURL": "https://example.com/p.jpg",
            "counts": ["answers": 2],
        ] as [String: Any])

        #expect(summary == AccountDeletionSummary(profileImageURL: "https://example.com/p.jpg"))
    }

    @Test func successResponseWithoutAPhotoHasNoURL() throws {
        // The callable sends null when the user had no photo; an empty string means the same.
        for profileImageURL in [NSNull() as Any, "" as Any] {
            let summary = try LiveAccountDeletionOperations.summary(fromCallableData: [
                "success": true,
                "profileImageURL": profileImageURL,
            ] as [String: Any])

            #expect(summary.profileImageURL == nil)
        }
    }

    @Test func responseWithoutSuccessIsAFailure() {
        #expect(throws: AccountDeletionError.dataDeletionFailed) {
            try LiveAccountDeletionOperations.summary(fromCallableData: ["success": false] as [String: Any])
        }
        #expect(throws: AccountDeletionError.dataDeletionFailed) {
            try LiveAccountDeletionOperations.summary(fromCallableData: [String: Any]())
        }
    }

    @Test func responseThatIsNotAnObjectIsAFailure() {
        #expect(throws: AccountDeletionError.dataDeletionFailed) {
            try LiveAccountDeletionOperations.summary(fromCallableData: NSNull())
        }
    }
}
