import Foundation
@testable import TTB

actor ContinuationAISuggestionService: AISuggestionServiceProtocol {
    private var resultsByTopic: [String: TrioQuestionSuggestionResult] = [:]
    private var blockedTopics: Set<String> = []
    private var startedTopics: Set<String> = []
    private var requestStartedContinuations:
        [String: CheckedContinuation<Void, Never>] = [:]
    private var resultContinuations:
        [String: CheckedContinuation<TrioQuestionSuggestionResult, Never>] = [:]

    func generateVariations(for topic: String, count: Int) async throws -> [String] {
        let result = try await generateSuggestions(
            for: topic,
            count: count,
            excluding: [],
            availableCategoryIDs: ["Daily"]
        )
        return result.suggestions
    }

    func generateSuggestions(
        for topic: String,
        count: Int,
        excluding: [String],
        availableCategoryIDs: [String]
    ) async throws -> TrioQuestionSuggestionResult {
        _ = count
        _ = excluding
        startedTopics.insert(topic)
        requestStartedContinuations.removeValue(forKey: topic)?.resume()

        if blockedTopics.contains(topic) {
            return await withCheckedContinuation { continuation in
                resultContinuations[topic] = continuation
            }
        }

        return resultsByTopic[topic] ?? TrioQuestionSuggestionResult(
            suggestions: [],
            suggestedCategoryID: availableCategoryIDs.first ?? "Daily"
        )
    }

    func setResult(_ result: TrioQuestionSuggestionResult, for topic: String) {
        resultsByTopic[topic] = result
    }

    func block(topic: String) {
        blockedTopics.insert(topic)
    }

    func waitUntilRequestStarts(for topic: String) async {
        guard !startedTopics.contains(topic) else { return }
        await withCheckedContinuation { continuation in
            requestStartedContinuations[topic] = continuation
        }
    }

    func resume(topic: String) {
        blockedTopics.remove(topic)
        let result = resultsByTopic[topic] ?? TrioQuestionSuggestionResult(
            suggestions: [],
            suggestedCategoryID: "Daily"
        )
        resultContinuations.removeValue(forKey: topic)?.resume(returning: result)
    }
}
