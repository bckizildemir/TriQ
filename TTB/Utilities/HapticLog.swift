import Foundation
import os

/// One log line per haptic the app asks for, so a simulator check can prove a haptic fired.
///
/// The simulator plays no haptics. Stream the line with:
/// `xcrun simctl spawn <UDID> log stream --predicate 'category == "Haptics"'`.
enum HapticLog {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.ttb.app",
        category: "Haptics"
    )

    /// Logs `haptic <event>` at notice level, which `log stream` shows by default.
    static func record(_ event: String) {
        logger.notice("haptic \(event, privacy: .public)")
    }
}
