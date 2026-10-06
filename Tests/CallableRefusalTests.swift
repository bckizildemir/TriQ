import FirebaseFunctions
import Foundation
import Testing
@testable import TTB

struct CallableRefusalTests {
    private static func functionsError(
        _ code: FunctionsErrorCode,
        reason: String? = nil,
        message: String = "Server text."
    ) -> NSError {
        var userInfo: [String: Any] = [NSLocalizedDescriptionKey: message]
        if let reason {
            userInfo[FunctionsErrorDetailsKey] = ["reason": reason]
        }
        return NSError(domain: FunctionsErrorDomain, code: code.rawValue, userInfo: userInfo)
    }

    // Raw codes, because FunctionsErrorCode is not Sendable and test arguments must be.
    @Test(arguments: [
        (FunctionsErrorCode.resourceExhausted.rawValue, "daily-limit", CallableRefusal.dailyLimit),
        (FunctionsErrorCode.resourceExhausted.rawValue, "project-daily-limit", .serviceBusyToday),
        (FunctionsErrorCode.resourceExhausted.rawValue, "project-minute-limit", .tryAgainShortly),
        (FunctionsErrorCode.unauthenticated.rawValue, "app-check-replay", .appVerification),
    ])
    func serverReasonMapsToItsRefusal(code: Int, reason: String, expected: CallableRefusal) throws {
        let code = try #require(FunctionsErrorCode(rawValue: code))
        #expect(CallableRefusal(Self.functionsError(code, reason: reason)) == expected)
    }

    @Test func unnamedResourceExhaustedAsksTheUserToWait() {
        #expect(CallableRefusal(Self.functionsError(.resourceExhausted)) == .tryAgainShortly)
    }

    @Test func unauthenticatedWithoutAReasonIsAnAppCheckRefusal() {
        // enforceAppCheck rejects a missing or invalid token with no details.
        #expect(CallableRefusal(Self.functionsError(.unauthenticated)) == .appVerification)
    }

    @Test func providerKeyFaultIsNotARefusal() {
        let error = Self.functionsError(.unauthenticated, message: "The AI provider key was rejected.")
        #expect(CallableRefusal(error) == nil)
    }

    @Test func otherCodesAndDomainsAreNotRefusals() {
        #expect(CallableRefusal(Self.functionsError(.dataLoss, reason: "daily-limit")) == nil)
        let urlError = NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut)
        #expect(CallableRefusal(urlError) == nil)
    }

    @Test func messagesNeverShowTheServerText() {
        let now = Date(timeIntervalSince1970: 1_785_484_800) // 2026-07-31T08:00:00Z
        for refusal in [CallableRefusal.dailyLimit, .serviceBusyToday, .tryAgainShortly, .appVerification] {
            let message = refusal.message(now: now)
            #expect(!message.isEmpty)
            #expect(!message.contains("Server text."))
        }
    }

    @Test func limitsResetAtTheNextUTCMidnight() {
        let lateUTC = Date(timeIntervalSince1970: 1_785_538_800) // 2026-07-31T23:00:00Z
        #expect(CallableRefusal.nextReset(after: lateUTC) == Date(timeIntervalSince1970: 1_785_542_400))

        let justAfterMidnight = Date(timeIntervalSince1970: 1_785_542_401) // 2026-08-01T00:00:01Z
        #expect(CallableRefusal.nextReset(after: justAfterMidnight) == Date(timeIntervalSince1970: 1_785_628_800))
    }
}
