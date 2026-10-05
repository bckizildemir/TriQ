import Foundation
@testable import TTB

actor MockAIService: AIServiceProtocol {
    var shouldFail = false
    private var blockedQuestions: Set<String> = []
    private var startedQuestions: Set<String> = []
    private var questionContinuations: [String: CheckedContinuation<Void, Never>] = [:]
    private var questionStartedContinuations: [String: CheckedContinuation<Void, Never>] = [:]
    var mockGeneratedQuestionPrompt = "Bu fikirden yola cikarak 3 cevapli bir soru uret."
    var mockSuggestedAnswers = [
        "Bu deneyim benim icin cok anlamliydi cunku kendimi daha iyi tanidim.",
        "Farkli bir perspektiften bakinca durumu daha net gorebildim.",
        "Adim adim ilerlemeyi ve sabirli olmayi tercih ettim."
    ]
    var mockQuestionVariations = [
        "What are the top 3 parts of this topic?",
        "Which 3 moments from this topic stand out most?",
        "What 3 things make this topic memorable?"
    ]
    var mockSuggestedCategoryID = "Daily"

    func askQuestion(_ question: String, category: AICategory) async throws -> [String] {
        startedQuestions.insert(question)
        questionStartedContinuations.removeValue(forKey: question)?.resume()
        if blockedQuestions.contains(question) {
            await withCheckedContinuation { continuation in
                questionContinuations[question] = continuation
            }
        }

        if shouldFail {
            throw AIServiceError.networkError(URLError(.notConnectedToInternet))
        }

        if question.localizedCaseInsensitiveContains("harry potter") {
            return [
                "Harry Potter ve Felsefe Tasi - Serinin baslangici",
                "Harry Potter ve Azkaban Tutsagi - En sevilen kitap",
                "Harry Potter ve Melez Prens - Derin hikaye"
            ]
        }

        switch category {
        case .recommendations:
            return [
                "Ilk onerim: Bu konuda arastirma yapin",
                "Ikinci onerim: Uzmanlardan yardim alin",
                "Ucuncu onerim: Kendi deneyimlerinizi degerlendirin"
            ]
        case .advice:
            return [
                "Birinci tavsiyem: Sabirli olun",
                "Ikinci tavsiyem: Planli hareket edin",
                "Ucuncu tavsiyem: Kendinize guvenin"
            ]
        case .learning:
            return [
                "Ogrenme onerisi 1: Duzenli calisin",
                "Ogrenme onerisi 2: Pratik yapin",
                "Ogrenme onerisi 3: Tekrar edin"
            ]
        case .productivity:
            return [
                "Bu konu hakkinda ilk oneri",
                "Bu konu hakkinda ikinci oneri",
                "Bu konu hakkinda ucuncu oneri"
            ]
        default:
            return [
                "Mock response 1 for \(category.rawValue)",
                "Mock response 2 for \(category.rawValue)",
                "Mock response 3 for \(category.rawValue)"
            ]
        }
    }

    func suggestAnswers(for question: String) async throws -> [String] {
        if shouldFail {
            throw AIServiceError.networkError(URLError(.notConnectedToInternet))
        }

        return mockSuggestedAnswers
    }

    func suggestQuickAnswers(
        for question: String,
        category: String,
        excluding: [String],
        languageName: String?,
        limit: Int
    ) async throws -> [String] {
        _ = question
        _ = category
        _ = languageName
        if shouldFail {
            throw AIServiceError.networkError(URLError(.notConnectedToInternet))
        }

        return QuickAnswerSuggestionResolver.merge(
            localCandidates: [],
            aiCandidates: mockSuggestedAnswers,
            excluding: excluding,
            limit: limit
        )
    }

    func generateQuestionPrompt(from idea: String, category: String) async throws -> String {
        if shouldFail {
            throw AIServiceError.networkError(URLError(.notConnectedToInternet))
        }

        if mockGeneratedQuestionPrompt.isEmpty {
            return "\(category) icin \(idea) fikrinden yola cikan bir soru"
        }

        return mockGeneratedQuestionPrompt
    }

    func generateQuestionVariations(from topic: String, count: Int) async throws -> [String] {
        if shouldFail {
            throw AIServiceError.networkError(URLError(.notConnectedToInternet))
        }

        if mockQuestionVariations.isEmpty {
            return (1...count).map { "Question variation \($0) for \(topic)?" }
        }

        return Array(mockQuestionVariations.prefix(count))
    }

    func generateTrioQuestionSuggestions(
        from topic: String,
        count: Int,
        excluding: [String],
        availableCategoryIDs: [String]
    ) async throws -> TrioQuestionSuggestionResult {
        _ = excluding
        if shouldFail {
            throw AIServiceError.networkError(URLError(.notConnectedToInternet))
        }

        let suggestions = mockQuestionVariations.isEmpty
            ? (1...count).map { "Question suggestion \($0) for \(topic)?" }
            : Array(mockQuestionVariations.prefix(count))
        let categoryID = availableCategoryIDs.contains(mockSuggestedCategoryID)
            ? mockSuggestedCategoryID
            : (availableCategoryIDs.first ?? "Daily")

        return TrioQuestionSuggestionResult(
            suggestions: suggestions,
            suggestedCategoryID: categoryID
        )
    }

    func setShouldFail(_ value: Bool) {
        shouldFail = value
    }

    func setSuggestedAnswers(_ answers: [String]) {
        mockSuggestedAnswers = answers
    }

    func setGeneratedQuestionPrompt(_ prompt: String) {
        mockGeneratedQuestionPrompt = prompt
    }

    func setQuestionVariations(_ variations: [String]) {
        mockQuestionVariations = variations
    }

    func setSuggestedCategoryID(_ categoryID: String) {
        mockSuggestedCategoryID = categoryID
    }

    func blockQuestion(_ question: String) {
        blockedQuestions.insert(question)
    }

    func waitUntilQuestionStarts(_ question: String) async {
        guard !startedQuestions.contains(question) else { return }
        await withCheckedContinuation { continuation in
            questionStartedContinuations[question] = continuation
        }
    }

    func hasQuestionStarted(_ question: String) -> Bool {
        startedQuestions.contains(question)
    }

    func resumeQuestion(_ question: String) {
        blockedQuestions.remove(question)
        questionContinuations.removeValue(forKey: question)?.resume()
    }

}

actor MockAISuggestionService: AISuggestionServiceProtocol {
    var shouldFail = false
    var variationsByTopic: [String: [String]] = [:]
    var suggestedCategoryByTopic: [String: String] = [:]
    var lastExcluding: [String] = []
    var lastTopic: String?
    var lastAvailableCategoryIDs: [String] = []
    var generateSuggestionsCallCount = 0
    var defaultVariations = [
        "What are the 3 best things about this topic?",
        "Which 3 examples of this topic matter most?",
        "What 3 parts of this topic would you rank highest?"
    ]

    func generateVariations(for topic: String, count: Int) async throws -> [String] {
        if shouldFail {
            throw AIServiceError.networkError(URLError(.notConnectedToInternet))
        }

        let variations = variationsByTopic[topic] ?? defaultVariations
        return Array(variations.prefix(count))
    }

    func generateSuggestions(
        for topic: String,
        count: Int,
        excluding: [String],
        availableCategoryIDs: [String]
    ) async throws -> TrioQuestionSuggestionResult {
        generateSuggestionsCallCount += 1
        lastTopic = topic
        lastExcluding = excluding
        lastAvailableCategoryIDs = availableCategoryIDs
        let suggestions = try await generateVariations(for: topic, count: count)
        let suggestedCategoryID = suggestedCategoryByTopic[topic]
            ?? availableCategoryIDs.first
            ?? "Daily"

        return TrioQuestionSuggestionResult(
            suggestions: suggestions,
            suggestedCategoryID: suggestedCategoryID
        )
    }

    func setShouldFail(_ value: Bool) {
        shouldFail = value
    }

    func setVariations(_ variations: [String], for topic: String) {
        variationsByTopic[topic] = variations
    }

    func setSuggestedCategoryID(_ categoryID: String, for topic: String) {
        suggestedCategoryByTopic[topic] = categoryID
    }

    func getLastExcluding() -> [String] {
        lastExcluding
    }

    func getLastTopic() -> String? {
        lastTopic
    }

    func getGenerateSuggestionsCallCount() -> Int {
        generateSuggestionsCallCount
    }
}

actor MockAIUsageService: AIUsageServiceProtocol {
    enum MockError: LocalizedError {
        case updateFailed

        var errorDescription: String? {
            "Usage persistence failed."
        }
    }

    var mockUsageStats = AIUsageStats()
    var mockCanMakeQuery = true
    var getUsageStatsCalled = false
    var updateUsageStatsCalled = false
    var canMakeQueryCalled = false
    var updateUsageError: MockError?
    private var blockedDailyQueryCounts: Set<Int> = []
    private var startedDailyQueryCounts: Set<Int> = []
    private var updateContinuations: [Int: CheckedContinuation<Void, Never>] = [:]
    private var updateStartedContinuations: [Int: CheckedContinuation<Void, Never>] = [:]
    private var persistedDailyQueryCounts: [Int] = []
    private var blocksUsageReads = false
    private var usageReadCallCount = 0
    private var usageReadContinuations: [CheckedContinuation<Void, Never>] = []
    private var usageReadStartedContinuations: [
        Int: [CheckedContinuation<Void, Never>]
    ] = [:]

    init(userId: String = "test-user") {
        _ = userId
    }

    func getUsageStats() async throws -> AIUsageStats {
        getUsageStatsCalled = true
        let snapshot = mockUsageStats
        usageReadCallCount += 1
        let startedCallCount = usageReadCallCount
        let startedKeys = usageReadStartedContinuations.keys.filter {
            $0 <= startedCallCount
        }
        let startedContinuations = startedKeys.flatMap {
            usageReadStartedContinuations.removeValue(forKey: $0) ?? []
        }
        startedContinuations.forEach { $0.resume() }

        if blocksUsageReads {
            await withCheckedContinuation { continuation in
                usageReadContinuations.append(continuation)
            }
        }
        return snapshot
    }

    func updateUsageStats(_ stats: AIUsageStats) async throws {
        updateUsageStatsCalled = true
        startedDailyQueryCounts.insert(stats.dailyQueries)
        updateStartedContinuations.removeValue(forKey: stats.dailyQueries)?.resume()
        if blockedDailyQueryCounts.contains(stats.dailyQueries) {
            await withCheckedContinuation { continuation in
                updateContinuations[stats.dailyQueries] = continuation
            }
        }
        if let updateUsageError {
            throw updateUsageError
        }
        mockUsageStats = stats
        persistedDailyQueryCounts.append(stats.dailyQueries)
    }

    func canMakeQuery() async throws -> Bool {
        canMakeQueryCalled = true
        return mockCanMakeQuery
    }

    func setMockCanMakeQuery(_ value: Bool) {
        mockCanMakeQuery = value
    }

    func setMockUsageStats(_ stats: AIUsageStats) {
        mockUsageStats = stats
    }

    func blockGetUsageStats() {
        blocksUsageReads = true
    }

    func getUsageStatsCallCount() -> Int {
        usageReadCallCount
    }

    func waitUntilGetUsageStatsStarts(callCount: Int) async {
        guard usageReadCallCount < callCount else { return }
        await withCheckedContinuation { continuation in
            usageReadStartedContinuations[callCount, default: []].append(continuation)
        }
    }

    func resumeGetUsageStats() {
        blocksUsageReads = false
        let continuations = usageReadContinuations
        usageReadContinuations.removeAll()
        continuations.forEach { $0.resume() }
    }

    func getUpdateUsageStatsCalled() -> Bool {
        updateUsageStatsCalled
    }

    func setUpdateUsageError(_ error: MockError?) {
        updateUsageError = error
    }

    func blockUpdate(dailyQueries: Int) {
        blockedDailyQueryCounts.insert(dailyQueries)
    }

    func waitUntilUpdateStarts(dailyQueries: Int) async {
        guard !startedDailyQueryCounts.contains(dailyQueries) else { return }
        await withCheckedContinuation { continuation in
            updateStartedContinuations[dailyQueries] = continuation
        }
    }

    func hasUpdateStarted(dailyQueries: Int) -> Bool {
        startedDailyQueryCounts.contains(dailyQueries)
    }

    func resumeUpdate(dailyQueries: Int) {
        blockedDailyQueryCounts.remove(dailyQueries)
        updateContinuations.removeValue(forKey: dailyQueries)?.resume()
    }

    func getPersistedDailyQueryCounts() -> [Int] {
        persistedDailyQueryCounts
    }
}
