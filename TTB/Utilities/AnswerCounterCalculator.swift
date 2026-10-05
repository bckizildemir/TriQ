import Foundation

enum AnswerCounterCalculator {
    static func incremented(_ storedValue: Int) -> Int {
        adding(1, to: storedValue)
    }

    static func adding(_ delta: Int, to storedValue: Int) -> Int {
        let normalizedValue = max(0, storedValue)
        let (result, overflowed) = normalizedValue.addingReportingOverflow(delta)
        return overflowed ? Int.max : result
    }
}
