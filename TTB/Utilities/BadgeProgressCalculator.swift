import Foundation

enum BadgeProgressCalculator {
    static func progress(currentCount: Int, targetCount: Int) -> Double {
        guard currentCount > 0, targetCount > 0 else { return 0 }
        guard currentCount < targetCount else { return 1 }
        return Double(currentCount) / Double(targetCount)
    }
}
