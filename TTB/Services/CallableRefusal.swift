import FirebaseFunctions
import Foundation

/// Why the server refused a callable before it did any work: a spend limit, or an App Check token it
/// would not accept. The server names the reason in the error details
/// (`functions/aiUsageLimit.js`, `functions/appCheckReplay.js`); the error message itself is English
/// server text, so it must never reach the user as-is.
enum CallableRefusal: Equatable {
    /// The caller's own daily limit for this feature is spent (`daily-limit`).
    case dailyLimit
    /// The project-wide pool for today is spent (`project-daily-limit`).
    case serviceBusyToday
    /// The project-wide per-minute limit is spent (`project-minute-limit`), or an unnamed
    /// `resource-exhausted`.
    case tryAgainShortly
    /// The App Check token was missing, invalid, or already used (`app-check-replay`).
    case appVerification

    /// The refusal this error carries, or nil when it is not one. An `unauthenticated` error that
    /// names the provider key is a server configuration fault, not an App Check refusal.
    init?(_ error: NSError) {
        guard error.domain == FunctionsErrorDomain else { return nil }
        let details = error.userInfo[FunctionsErrorDetailsKey] as? [String: Any]
        let reason = details?["reason"] as? String

        switch FunctionsErrorCode(rawValue: error.code) {
        case .resourceExhausted:
            switch reason {
            case "daily-limit": self = .dailyLimit
            case "project-daily-limit": self = .serviceBusyToday
            default: self = .tryAgainShortly
            }
        case .unauthenticated:
            if reason == "app-check-replay" {
                self = .appVerification
            } else if error.localizedDescription.lowercased().contains("provider key") {
                return nil
            } else {
                self = .appVerification
            }
        default:
            return nil
        }
    }

    var message: String {
        message(now: .now)
    }

    func message(now: Date) -> String {
        switch self {
        case .dailyLimit:
            return String(
                format: String(localized: "callable.error.dailyLimit"),
                locale: AppLocalization.currentLocale,
                Self.nextReset(after: now).formatted(date: .omitted, time: .shortened)
            )
        case .serviceBusyToday:
            return String(localized: "callable.error.serviceBusyToday")
        case .tryAgainShortly:
            return String(localized: "ai.error.rateLimit")
        case .appVerification:
            return String(localized: "callable.error.appVerification")
        }
    }

    /// The server counts days in UTC, so a limit resets at the next UTC midnight, whatever the
    /// device's time zone.
    static func nextReset(after now: Date) -> Date {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = .gmt
        let startOfToday = utc.startOfDay(for: now)
        return utc.date(byAdding: .day, value: 1, to: startOfToday) ?? startOfToday.addingTimeInterval(86_400)
    }
}
