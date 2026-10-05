import Foundation

// MARK: - AI Suggestion Service Protocol
struct TrioQuestionSuggestionResult: Equatable {
    let suggestions: [String]
    let suggestedCategoryID: String
}

protocol AISuggestionServiceProtocol {
    func generateVariations(for topic: String, count: Int) async throws -> [String]
    func generateSuggestions(
        for topic: String,
        count: Int,
        excluding: [String],
        availableCategoryIDs: [String]
    ) async throws -> TrioQuestionSuggestionResult
}

// MARK: - AI Suggestion Service
@MainActor
final class AISuggestionService: AISuggestionServiceProtocol {
    private let aiService: AIServiceProtocol

    init(aiService: AIServiceProtocol = AIService()) {
        self.aiService = aiService
    }

    func generateVariations(for topic: String, count: Int) async throws -> [String] {
        let variations = try await aiService.generateQuestionVariations(from: topic, count: count)
        return Array(variations.prefix(count))
    }

    func generateSuggestions(
        for topic: String,
        count: Int,
        excluding: [String],
        availableCategoryIDs: [String]
    ) async throws -> TrioQuestionSuggestionResult {
        try await aiService.generateTrioQuestionSuggestions(
            from: topic,
            count: count,
            excluding: excluding,
            availableCategoryIDs: availableCategoryIDs
        )
    }
}
