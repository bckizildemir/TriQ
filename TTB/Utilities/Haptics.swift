import Foundation
import os
import UIKit

/// Plays the app's one-shot haptics, and logs each one at the moment it fires.
///
/// UIKit generators, not `.sensoryFeedback`: these fire from a tap whose view may leave in the
/// same update (an unstarred card on Favorites, an editor that closes on save), and a SwiftUI
/// feedback trigger on a leaving view may never play.
///
/// The simulator plays no haptics, so a check proves them from the log line `haptic <event>`:
/// `xcrun simctl spawn <UDID> log stream --predicate 'category == "Haptics"'`.
@MainActor
enum Haptics {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.ttb.app",
        category: "Haptics"
    )

    /// A light impact, the haptic for a tap (#56).
    static func playLightImpact(for event: String) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        log(event)
    }

    /// The success notification, for something that really happened (a save that started).
    static func playSuccess(for event: String) {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        log(event)
    }

    /// Logs `haptic <event>` at notice level, which `log stream` shows by default.
    private static func log(_ event: String) {
        logger.notice("haptic \(event, privacy: .public)")
    }
}
