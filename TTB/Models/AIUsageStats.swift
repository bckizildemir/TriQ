//
//  AIUsageStats.swift
//  TTB
//
//  Created by AI Assistant on 2025-07-18.
//

import Foundation
import FirebaseFirestore

struct AIUsageStats: Codable {
    let dailyQueries: Int
    let weeklyQueries: Int
    let monthlyQueries: Int
    let totalQueries: Int
    let lastQueryDate: Date?
    let favoriteCategory: AICategory?
    let lastResetDate: Date
    
    // MARK: - Usage Limits
    var dailyLimit: Int { 20 }
    var weeklyLimit: Int { 100 }
    var monthlyLimit: Int { 300 }
    
    // MARK: - Computed Properties
    var canMakeQuery: Bool { 
        dailyQueries < dailyLimit && weeklyQueries < weeklyLimit && monthlyQueries < monthlyLimit
    }
    
    var remainingDailyQueries: Int { 
        max(0, dailyLimit - dailyQueries)
    }
    
    var remainingWeeklyQueries: Int { 
        max(0, weeklyLimit - weeklyQueries)
    }
    
    var remainingMonthlyQueries: Int { 
        max(0, monthlyLimit - monthlyQueries)
    }
    
    var usagePercentage: Double {
        return Double(dailyQueries) / Double(dailyLimit)
    }
    
    var isNearLimit: Bool {
        usagePercentage >= 0.8
    }
    
    var isAtLimit: Bool {
        dailyQueries >= dailyLimit
    }
    
    // MARK: - Initialization
    init(
        dailyQueries: Int = 0,
        weeklyQueries: Int = 0,
        monthlyQueries: Int = 0,
        totalQueries: Int = 0,
        lastQueryDate: Date? = nil,
        favoriteCategory: AICategory? = nil,
        lastResetDate: Date = Date()
    ) {
        self.dailyQueries = max(0, dailyQueries)
        self.weeklyQueries = max(0, weeklyQueries)
        self.monthlyQueries = max(0, monthlyQueries)
        self.totalQueries = max(0, totalQueries)
        self.lastQueryDate = lastQueryDate
        self.favoriteCategory = favoriteCategory
        self.lastResetDate = lastResetDate
    }
    
    // MARK: - Usage Methods
    func incrementUsage(category: AICategory) -> AIUsageStats {
        let now = Date()
        let calendar = Calendar.current
        
        // Check if we need to reset counters
        var newDailyQueries = dailyQueries
        var newWeeklyQueries = weeklyQueries
        var newMonthlyQueries = monthlyQueries
        var newLastResetDate = lastResetDate
        
        // Reset daily counter if it's a new day
        if !calendar.isDate(now, inSameDayAs: lastResetDate) {
            newDailyQueries = 0
            newLastResetDate = now
        }
        
        // Reset weekly counter if it's a new week
        if !calendar.isDate(now, equalTo: lastResetDate, toGranularity: .weekOfYear) {
            newWeeklyQueries = 0
        }
        
        // Reset monthly counter if it's a new month
        if !calendar.isDate(now, equalTo: lastResetDate, toGranularity: .month) {
            newMonthlyQueries = 0
        }
        
        // Update favorite category
        let newFavoriteCategory = updateFavoriteCategory(with: category)
        
        return AIUsageStats(
            dailyQueries: AnswerCounterCalculator.incremented(newDailyQueries),
            weeklyQueries: AnswerCounterCalculator.incremented(newWeeklyQueries),
            monthlyQueries: AnswerCounterCalculator.incremented(newMonthlyQueries),
            totalQueries: AnswerCounterCalculator.incremented(totalQueries),
            lastQueryDate: now,
            favoriteCategory: newFavoriteCategory,
            lastResetDate: newLastResetDate
        )
    }

    private func updateFavoriteCategory(with category: AICategory) -> AICategory {
        // Simple logic: if this is the first query or same category, return it
        // In a real implementation, you'd track category counts
        return favoriteCategory ?? category
    }
    
    // MARK: - Firebase Integration
    func toFirestore() -> [String: Any] {
        var data: [String: Any] = [
            "dailyQueries": dailyQueries,
            "weeklyQueries": weeklyQueries,
            "monthlyQueries": monthlyQueries,
            "totalQueries": totalQueries,
            "lastResetDate": Timestamp(date: lastResetDate)
        ]
        
        if let lastQueryDate = lastQueryDate {
            data["lastQueryDate"] = Timestamp(date: lastQueryDate)
        }
        
        if let favoriteCategory = favoriteCategory {
            data["favoriteCategory"] = favoriteCategory.rawValue
        }
        
        return data
    }
    
    static func fromFirestore(_ data: [String: Any]) -> AIUsageStats? {
        guard let dailyQueries = data["dailyQueries"] as? Int,
              let weeklyQueries = data["weeklyQueries"] as? Int,
              let monthlyQueries = data["monthlyQueries"] as? Int,
              let totalQueries = data["totalQueries"] as? Int,
              let lastResetTimestamp = data["lastResetDate"] as? Timestamp else {
            return nil
        }
        
        let lastQueryDate = (data["lastQueryDate"] as? Timestamp)?.dateValue()
        let favoriteCategory = (data["favoriteCategory"] as? String).flatMap { AICategory(rawValue: $0) }
        
        return AIUsageStats(
            dailyQueries: dailyQueries,
            weeklyQueries: weeklyQueries,
            monthlyQueries: monthlyQueries,
            totalQueries: totalQueries,
            lastQueryDate: lastQueryDate,
            favoriteCategory: favoriteCategory,
            lastResetDate: lastResetTimestamp.dateValue()
        )
    }
}

// MARK: - Usage Stats Extensions
extension AIUsageStats {
    var formattedUsageText: String {
        String(
            format: String(localized: "ai.usage.label"),
            locale: AppLocalization.currentLocale,
            dailyQueries,
            dailyLimit
        )
    }
    
    var detailedUsageText: String {
        return """
        Günlük: \(dailyQueries)/\(dailyLimit)
        Haftalık: \(weeklyQueries)/\(weeklyLimit)
        Aylık: \(monthlyQueries)/\(monthlyLimit)
        Toplam: \(totalQueries)
        """
    }
    
    var warningMessage: String? {
        if isAtLimit {
            return String(localized: "ai.usage.limitReached")
        } else if isNearLimit {
            return String(
                format: String(localized: "ai.usage.approachingLimit"),
                locale: AppLocalization.currentLocale,
                remainingDailyQueries
            )
        }
        return nil
    }
}

// MARK: - Sample Data
extension AIUsageStats {
    static let sample = AIUsageStats(
        dailyQueries: 5,
        weeklyQueries: 12,
        monthlyQueries: 45,
        totalQueries: 156,
        lastQueryDate: Date(),
        favoriteCategory: .recommendations,
        lastResetDate: Date()
    )
    
    static let nearLimit = AIUsageStats(
        dailyQueries: 18,
        weeklyQueries: 85,
        monthlyQueries: 250,
        totalQueries: 500,
        lastQueryDate: Date(),
        favoriteCategory: .productivity,
        lastResetDate: Date()
    )
    
    static let atLimit = AIUsageStats(
        dailyQueries: 20,
        weeklyQueries: 100,
        monthlyQueries: 300,
        totalQueries: 800,
        lastQueryDate: Date(),
        favoriteCategory: .learning,
        lastResetDate: Date()
    )
}
