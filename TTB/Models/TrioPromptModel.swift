import FirebaseAuth
import Foundation

@MainActor
final class TrioPromptModel: ObservableObject {
    @Published var ideaText = ""
    @Published var draftQuestion = ""
    @Published var selectedCategory = Category.defaultCategories.first?.id ?? "Daily"
    @Published private(set) var isGenerating = false
    @Published private(set) var isPublishing = false
    @Published private(set) var usageStats = AIUsageStats()
    @Published var error: String?
    @Published var successMessage: String?

    let minimumQuestionLength = 8
    let maximumQuestionLength = 180
    let minimumWordsForAutoSuggestions = 2

    // MARK: - Suggestion Chips
    @Published var suggestedVariations: [String] = []
    @Published private(set) var isGeneratingSuggestions: Bool = false
    @Published var selectedVariation: String? = nil
    @Published var suggestedCategoryID: String? = nil
    @Published private(set) var hasManualCategoryOverride = false

    private var suggestionRequestID = 0
    private var isApplyingSelectedVariation = false
    private var pendingSelectedVariationDraft: String?
    private var shownSuggestionHistory: [String] = []
    private let suggestionService: AISuggestionServiceProtocol

    private let aiService: AIServiceProtocol
    private let usageService: AIUsageServiceProtocol?
    private let apiKeyValidator: () -> Bool

    init(
        aiService: AIServiceProtocol = AIService(),
        suggestionService: AISuggestionServiceProtocol? = nil,
        usageService: AIUsageServiceProtocol? = nil,
        initialUsageStats: AIUsageStats? = nil,
        apiKeyValidator: @escaping () -> Bool = { true }
    ) {
        self.aiService = aiService
        self.suggestionService = suggestionService ?? AISuggestionService(aiService: aiService)
        self.apiKeyValidator = apiKeyValidator
        if let usageService = usageService {
            self.usageService = usageService
        } else if let currentUser = Auth.auth().currentUser {
            self.usageService = AIUsageService(userId: currentUser.uid)
        } else {
            self.usageService = nil
        }

        if let initialUsageStats {
            self.usageStats = initialUsageStats
        } else {
            Task { @MainActor in
                await loadUsageStats()
            }
        }
    }

    var canGenerateDraft: Bool {
        isAIAvailable && !trimmedIdea.isEmpty && !isGenerating && !isPublishing && !hasReachedDailyLimit
    }

    var canPublish: Bool {
        trimmedDraft.count >= minimumQuestionLength
            && trimmedDraft.count <= maximumQuestionLength
            && !isPublishing
    }

    var isAIAvailable: Bool {
        apiKeyValidator()
    }

    var isAnonymousUser: Bool {
        Auth.auth().currentUser?.isAnonymous ?? false
    }

    var dailyLimit: Int {
        GuestCapabilityPolicy.dailyAILimit(isAnonymous: isAnonymousUser)
    }

    var hasReachedDailyLimit: Bool {
        usageStats.dailyQueries >= dailyLimit
    }

    var usageHint: String? {
        guard isAnonymousUser else { return nil }
        return String(
            format: String(localized: "ai.trio.usageHint"),
            locale: AppLocalization.currentLocale,
            dailyLimit
        )
    }

    var trimmedIdea: String {
        ideaText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedDraft: String {
        draftQuestion.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var questionCharacterCount: Int {
        draftQuestion.count
    }

    var questionValidationMessage: String? {
        let count = trimmedDraft.count
        guard count > 0 else { return nil }

        if count < minimumQuestionLength {
            return String(
                format: String(localized: "ai.trioComposer.validation.tooShort"),
                locale: AppLocalization.currentLocale,
                minimumQuestionLength
            )
        }

        if count > maximumQuestionLength {
            return String(
                format: String(localized: "ai.trioComposer.validation.tooLong"),
                locale: AppLocalization.currentLocale,
                maximumQuestionLength
            )
        }

        return nil
    }

    func generateDraft() async {
        guard canGenerateDraft else {
            if hasReachedDailyLimit {
                error = String(
                    format: String(localized: "ai.trio.limitReached"),
                    locale: AppLocalization.currentLocale,
                    dailyLimit
                )
            }
            return
        }

        error = nil
        successMessage = nil
        isGenerating = true
        defer { isGenerating = false }

        do {
            let generated = try await aiService.generateQuestionPrompt(
                from: trimmedIdea,
                category: selectedCategory
            )
            draftQuestion = normalizePrompt(generated)
            await incrementUsage()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func publish(using questionModel: QuestionModel) async -> Question? {
        guard canPublish else { return nil }

        error = nil
        successMessage = nil
        isPublishing = true
        defer { isPublishing = false }

        do {
            let question = try await questionModel.publishUserCreatedQuestion(
                text: normalizePrompt(trimmedDraft),
                category: selectedCategory
            )
            ideaText = ""
            draftQuestion = ""
            clearSuggestions()
            hasManualCategoryOverride = false
            successMessage = String(localized: "ai.trio.submitSuccess")
            return question
        } catch {
            self.error = error.localizedDescription
            return nil
        }
    }

    func clearMessages() {
        error = nil
        successMessage = nil
    }

    func onQuestionTextEdited(_ newText: String) {
        onQuestionTextEdited(
            newText,
            availableCategoryIDs: Category.defaultCategories.map(\.id)
        )
    }

    func onQuestionTextEdited(_ newText: String, availableCategoryIDs: [String]) {
        guard !isApplyingSelectedVariation else { return }
        if pendingSelectedVariationDraft == newText {
            pendingSelectedVariationDraft = nil
            return
        }
        pendingSelectedVariationDraft = nil

        suggestionRequestID += 1
        isGeneratingSuggestions = false
        error = nil
        selectedVariation = nil

        _ = availableCategoryIDs
    }

    // MARK: - Suggestion Chips

    /// Called while the user edits the question-idea field. Clears stale chips and errors without starting a network request.
    func onIdeaTextEdited(_ newText: String) {
        suggestionRequestID += 1

        let trimmed = newText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 3 else {
            error = nil
            if trimmedDraft.isEmpty {
                suggestedVariations = []
                selectedVariation = nil
                suggestedCategoryID = nil
            }
            isGeneratingSuggestions = false
            return
        }

        error = nil
        suggestedVariations = []
        selectedVariation = nil
        suggestedCategoryID = nil
    }

    func generateVariations(for topic: String) async {
        await generateSuggestions(
            for: topic,
            availableCategoryIDs: Category.defaultCategories.map(\.id),
            isManualRefresh: true
        )
    }

    func generateSuggestions(
        for topic: String,
        availableCategoryIDs: [String],
        isManualRefresh: Bool = true
    ) async {
        let trimmed = topic.trimmingCharacters(in: .whitespacesAndNewlines)
        guard wordCount(in: trimmed) >= minimumWordsForAutoSuggestions else { return }

        suggestionRequestID += 1
        await generateSuggestions(
            for: trimmed,
            availableCategoryIDs: availableCategoryIDs,
            requestID: suggestionRequestID,
            isManualRefresh: isManualRefresh
        )
    }

    private func generateSuggestions(
        for topic: String,
        availableCategoryIDs: [String],
        requestID: Int,
        isManualRefresh: Bool
    ) async {
        guard requestID == suggestionRequestID else {
            return
        }
        guard isAIAvailable else {
            isGeneratingSuggestions = false
            return
        }
        guard !hasReachedDailyLimit else {
            isGeneratingSuggestions = false
            return
        }

        error = nil
        isGeneratingSuggestions = true
        defer {
            if requestID == suggestionRequestID {
                isGeneratingSuggestions = false
            }
        }

        do {
            let excluding = Array(shownSuggestionHistory.suffix(20))
            let result = try await suggestionService.generateSuggestions(
                for: topic,
                count: 3,
                excluding: excluding,
                availableCategoryIDs: availableCategoryIDs
            )
            try Task.checkCancellation()
            guard requestID == suggestionRequestID else {
                return
            }
            suggestedVariations = result.suggestions
            suggestedCategoryID = result.suggestedCategoryID
            shownSuggestionHistory.append(contentsOf: result.suggestions)
            shownSuggestionHistory = Array(shownSuggestionHistory.suffix(40))
            if !hasManualCategoryOverride,
               availableCategoryIDs.contains(result.suggestedCategoryID) {
                selectedCategory = result.suggestedCategoryID
            }
            await incrementUsage()
        } catch is CancellationError {
            // no-op
        } catch {
            guard requestID == suggestionRequestID else {
                return
            }
            self.error = error.localizedDescription
            if isManualRefresh {
                suggestedVariations = []
                suggestedCategoryID = nil
            }
        }
    }

    func selectVariation(_ variation: String) {
        isApplyingSelectedVariation = true
        selectedVariation = variation
        let normalized = normalizePrompt(variation)
        pendingSelectedVariationDraft = normalized
        draftQuestion = normalized
        ideaText = ""
        isApplyingSelectedVariation = false
    }

    func selectCategory(_ categoryID: String) {
        selectedCategory = categoryID
        hasManualCategoryOverride = true
    }

    var shouldHandleIdeaTextEdits: Bool {
        !isApplyingSelectedVariation
    }

    func clearSuggestions() {
        suggestionRequestID += 1
        isGeneratingSuggestions = false
        suggestedVariations = []
        selectedVariation = nil
        suggestedCategoryID = nil
        error = nil
    }

    private func loadUsageStats() async {
        guard let usageService else { return }

        do {
            usageStats = try await usageService.getUsageStats()
        } catch {
            self.error = String(localized: "ai.trio.error.loadUsage")
        }
    }

    private func incrementUsage() async {
        guard let usageService else { return }

        let updatedStats = usageStats.incrementUsage(category: .other)
        usageStats = updatedStats

        try? await usageService.updateUsageStats(updatedStats)
    }

    private func normalizePrompt(_ prompt: String) -> String {
        let collapsed = prompt
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        guard !collapsed.isEmpty else { return "" }
        guard collapsed.hasSuffix("?") else {
            return collapsed + "?"
        }

        return collapsed
    }

    private func wordCount(in text: String) -> Int {
        text
            .split { $0.isWhitespace || $0.isNewline }
            .count
    }
}
