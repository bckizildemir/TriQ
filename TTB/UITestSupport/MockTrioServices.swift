import Foundation

#if DEBUG
actor UITestMockAISuggestionService: AISuggestionServiceProtocol {
    var shouldFail = false
    var defaultVariations = [
        "What are the top 3 travel memories that still feel vivid when you think about them?",
        "Which 3 moments from this topic stand out most?",
        "What 3 things make this topic memorable?"
    ]

    func generateVariations(for topic: String, count: Int) async throws -> [String] {
        _ = topic
        if shouldFail {
            throw AIServiceError.networkError(URLError(.notConnectedToInternet))
        }
        return Array(defaultVariations.prefix(count))
    }

    func generateSuggestions(
        for topic: String,
        count: Int,
        excluding: [String],
        availableCategoryIDs: [String]
    ) async throws -> TrioQuestionSuggestionResult {
        _ = topic
        _ = excluding
        if shouldFail {
            throw AIServiceError.networkError(URLError(.notConnectedToInternet))
        }
        return TrioQuestionSuggestionResult(
            suggestions: Array(defaultVariations.prefix(count)),
            suggestedCategoryID: availableCategoryIDs.first ?? "Daily"
        )
    }
}

actor UITestMockAIUsageService: AIUsageServiceProtocol {
    var mockUsageStats: AIUsageStats

    init(userId: String = "ui-test-user", usageStats: AIUsageStats = AIUsageStats()) {
        _ = userId
        mockUsageStats = usageStats
    }

    func getUsageStats() async throws -> AIUsageStats {
        mockUsageStats
    }

    func updateUsageStats(_ stats: AIUsageStats) async throws {
        mockUsageStats = stats
    }

    func canMakeQuery() async throws -> Bool {
        mockUsageStats.canMakeQuery
    }
}

enum UITestTrioModelFactory {
    @MainActor
    static func makeTrioModel() -> TrioPromptModel {
        TrioPromptModel(
            aiService: AIService(),
            suggestionService: UITestMockAISuggestionService(),
            usageService: UITestMockAIUsageService(),
            apiKeyValidator: { true }
        )
    }

    @MainActor
    static func makeTrioModelAtDailyLimit(isAnonymous: Bool) -> TrioPromptModel {
        let limit = GuestCapabilityPolicy.dailyAILimit(isAnonymous: isAnonymous)
        let usageStats = AIUsageStats(dailyQueries: limit)
        let usageService = UITestMockAIUsageService(usageStats: usageStats)
        return TrioPromptModel(
            aiService: AIService(),
            suggestionService: UITestMockAISuggestionService(),
            usageService: usageService,
            initialUsageStats: usageStats,
            apiKeyValidator: { true }
        )
    }
}
#endif
