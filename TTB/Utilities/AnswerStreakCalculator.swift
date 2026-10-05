import Foundation

enum AnswerStreakCalculator {
    static func updatedStreak(
        from lastAnsweredDate: Date?,
        currentStreak: Int,
        now: Date,
        calendar: Calendar
    ) -> Int {
        guard let lastAnsweredDate else { return 1 }

        let lastDay = calendar.startOfDay(for: lastAnsweredDate)
        let currentDay = calendar.startOfDay(for: now)
        let dayDifference = calendar.dateComponents(
            [.day],
            from: lastDay,
            to: currentDay
        ).day
        let sanitizedCurrentStreak = max(0, currentStreak)

        switch dayDifference {
        case 0:
            return sanitizedCurrentStreak
        case 1:
            return AnswerCounterCalculator.incremented(sanitizedCurrentStreak)
        default:
            return 1
        }
    }

    static func currentStreak(
        from dates: [Date],
        calendar: Calendar
    ) -> Int {
        let uniqueDays = Set(dates.map { calendar.startOfDay(for: $0) })
        let sortedDays = uniqueDays.sorted(by: >)
        guard let latestDay = sortedDays.first else { return 0 }

        var streak = 1
        var cursor = latestDay

        for day in sortedDays.dropFirst() {
            guard
                let previousDay = calendar.date(
                    byAdding: .day,
                    value: -1,
                    to: cursor
                ),
                calendar.isDate(day, inSameDayAs: previousDay)
            else {
                break
            }

            streak += 1
            cursor = day
        }

        return streak
    }
}
