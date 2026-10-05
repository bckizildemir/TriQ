import Foundation
import Testing
@testable import TTB

@MainActor
struct TrioPromptModelTests {
    @Test
    func defaultsToFirstDefaultCategoryID() {
        let model = TrioPromptModel(
            aiService: MockAIService(),
            usageService: nil,
            apiKeyValidator: { false }
        )

        #expect(model.selectedCategory == Category.defaultCategories.first?.id ?? "Daily")
    }

    @Test
    func generateDraftNormalizesPromptAndUpdatesUsage() async {
        let aiService = MockAIService()
        let usageService = MockAIUsageService()
        let initialUsageStats = AIUsageStats(
            dailyQueries: 2,
            weeklyQueries: 2,
            monthlyQueries: 2,
            totalQueries: 2
        )
        await aiService.setGeneratedQuestionPrompt("  Ask   better questions  ")

        let model = TrioPromptModel(
            aiService: aiService,
            usageService: usageService,
            initialUsageStats: initialUsageStats,
            apiKeyValidator: { true }
        )

        #expect(model.usageStats.dailyQueries == 2)

        model.ideaText = "communication"
        await model.generateDraft()

        #expect(model.draftQuestion == "Ask better questions?")
        #expect(model.usageStats.dailyQueries == 3)
        #expect(await usageService.getUpdateUsageStatsCalled())
        #expect(model.error == nil)
    }

    @Test
    func generateDraftSurfacesAIErrors() async {
        let aiService = MockAIService()
        await aiService.setShouldFail(true)

        let model = TrioPromptModel(
            aiService: aiService,
            usageService: nil,
            apiKeyValidator: { true }
        )

        model.ideaText = "travel"
        await model.generateDraft()

        #expect(model.error?.isEmpty == false)
        #expect(model.draftQuestion.isEmpty)
        #expect(model.usageStats.dailyQueries == 0)
    }

    @Test
    func finalQuestionTextEnablesPublishing() {
        let model = TrioPromptModel(
            aiService: MockAIService(),
            usageService: nil,
            apiKeyValidator: { true }
        )

        model.draftQuestion = "travel memories"

        #expect(model.trimmedDraft == "travel memories")
        #expect(model.canPublish)
    }

    @Test
    func finalQuestionValidationRejectsShortAndLongText() {
        let model = TrioPromptModel(
            aiService: MockAIService(),
            usageService: nil,
            apiKeyValidator: { true }
        )

        model.draftQuestion = "short"
        #expect(model.canPublish == false)
        #expect(model.questionValidationMessage != nil)

        model.draftQuestion = String(repeating: "x", count: model.maximumQuestionLength + 1)
        #expect(model.canPublish == false)
        #expect(model.questionValidationMessage != nil)
    }

    @Test
    func defaultAvailabilityDoesNotRequireBundledProviderKey() {
        let model = TrioPromptModel(
            aiService: MockAIService(),
            usageService: nil
        )

        model.ideaText = "travel memories"

        #expect(model.isAIAvailable)
        #expect(model.canGenerateDraft)
    }

    @Test
    func selectingVariationFillsEditableDraftAndEnablesPublishing() {
        let model = TrioPromptModel(
            aiService: MockAIService(),
            usageService: nil,
            apiKeyValidator: { true }
        )

        model.selectVariation("What are your 3 favorite travel memories")

        #expect(model.selectedVariation == "What are your 3 favorite travel memories")
        #expect(model.draftQuestion == "What are your 3 favorite travel memories?")
        #expect(model.ideaText.isEmpty)
        #expect(model.canPublish)
    }

    @Test
    func editingQuestionTextClearsSelectedSuggestionButKeepsVisibleSuggestions() {
        let model = TrioPromptModel(
            aiService: MockAIService(),
            usageService: nil,
            apiKeyValidator: { true }
        )

        model.suggestedVariations = ["What are your 3 favorite travel memories?"]
        model.selectVariation("What are your 3 favorite travel memories?")

        model.onQuestionTextEdited("What are your 3 favorite comfort foods?")

        #expect(model.selectedVariation == nil)
        #expect(model.suggestedVariations == ["What are your 3 favorite travel memories?"])
        #expect(model.isGeneratingSuggestions == false)
    }

    @Test
    func selectingSuggestionDoesNotTriggerAnotherSuggestionRequest() async {
        let suggestionService = MockAISuggestionService()
        await suggestionService.setVariations([
            "What are your 3 favorite travel memories?",
            "Which 3 cities would you visit again?",
            "What 3 travel moments stayed with you?"
        ], for: "travel memories")

        let model = TrioPromptModel(
            aiService: MockAIService(),
            suggestionService: suggestionService,
            usageService: nil,
            apiKeyValidator: { true }
        )

        await model.generateSuggestions(
            for: "travel memories",
            availableCategoryIDs: ["Daily", "Personal"]
        )
        #expect(await suggestionService.getGenerateSuggestionsCallCount() == 1)

        model.selectVariation("What are your 3 favorite travel memories?")
        model.onQuestionTextEdited(model.draftQuestion)

        #expect(model.selectedVariation == "What are your 3 favorite travel memories?")
        #expect(model.suggestedVariations.count == 3)
        #expect(model.isGeneratingSuggestions == false)
        #expect(await suggestionService.getGenerateSuggestionsCallCount() == 1)
    }

    @Test
    func publishUsesEditedFinalQuestionText() async {
        let model = TrioPromptModel(
            aiService: MockAIService(),
            usageService: nil,
            apiKeyValidator: { true }
        )
        let questionModel = QuestionModel(localQuestions: [])

        model.selectVariation("What are your 3 favorite travel memories?")
        model.draftQuestion = "  Which 3 trips would you repeat  "

        let publishedQuestion = await model.publish(using: questionModel)

        #expect(publishedQuestion?.fallbackText == "Which 3 trips would you repeat?")
        #expect(publishedQuestion?.source == .userCreated)
        #expect(publishedQuestion?.moderationStatus == .pending)
        #expect(publishedQuestion?.isAnnounced == false)
        #expect(questionModel.trioQuestions.isEmpty)
        #expect(model.draftQuestion.isEmpty)
        #expect(model.successMessage != nil)
        #expect(model.error == nil)
    }

    @Test
    func mockAIServiceGeneratesQuestionVariations() async throws {
        let aiService = MockAIService()
        await aiService.setQuestionVariations([
            "What are the 3 best travel memories?",
            "Which 3 trips would you repeat?",
            "What 3 places surprised you most?"
        ])

        let variations = try await aiService.generateQuestionVariations(from: "travel", count: 2)

        #expect(variations == [
            "What are the 3 best travel memories?",
            "Which 3 trips would you repeat?"
        ])
    }

    @Test
    func generateVariationsUpdatesSuggestionsAndUsage() async {
        let suggestionService = MockAISuggestionService()
        let usageService = MockAIUsageService()
        let initialUsageStats = AIUsageStats(
            dailyQueries: 2,
            weeklyQueries: 2,
            monthlyQueries: 2,
            totalQueries: 2
        )
        await suggestionService.setVariations([
            "What are your 3 favorite travel destinations?",
            "Which 3 cities would you visit again?",
            "What 3 travel moments stayed with you?"
        ], for: "travel memories")

        let model = TrioPromptModel(
            aiService: MockAIService(),
            suggestionService: suggestionService,
            usageService: usageService,
            initialUsageStats: initialUsageStats,
            apiKeyValidator: { true }
        )

        await model.generateVariations(for: "travel memories")

        #expect(model.suggestedVariations == [
            "What are your 3 favorite travel destinations?",
            "Which 3 cities would you visit again?",
            "What 3 travel moments stayed with you?"
        ])
        #expect(model.usageStats.dailyQueries == 3)
        #expect(model.error == nil)
    }

    @Test
    func ideaTextEditsClearSuggestionsWithoutNewNetworkRequest() async {
        let suggestionService = MockAISuggestionService()
        await suggestionService.setVariations([
            "What are your 3 favorite travel destinations?",
            "Which 3 cities would you visit again?",
            "What 3 travel moments stayed with you?"
        ], for: "travel memories")

        let model = TrioPromptModel(
            aiService: MockAIService(),
            suggestionService: suggestionService,
            usageService: nil,
            apiKeyValidator: { true }
        )

        await model.generateVariations(for: "travel memories")
        #expect(model.suggestedVariations.count == 3)

        model.onIdeaTextEdited("travel ")

        #expect(model.suggestedVariations.isEmpty)
        #expect(model.error == nil)
        #expect(model.isGeneratingSuggestions == false)
    }

    @Test
    func secondVariationRequestWhileFirstInFlightShowsLatestTopicOnly() async {
        let suggestionService = ContinuationAISuggestionService()
        await suggestionService.setResult(
            TrioQuestionSuggestionResult(
                suggestions: [
                    "Old suggestion 1?",
                    "Old suggestion 2?",
                    "Old suggestion 3?",
                ],
                suggestedCategoryID: "Daily"
            ),
            for: "first topic"
        )
        await suggestionService.setResult(
            TrioQuestionSuggestionResult(
                suggestions: [
                    "Final suggestion 1?",
                    "Final suggestion 2?",
                    "Final suggestion 3?",
                ],
                suggestedCategoryID: "Daily"
            ),
            for: "final topic"
        )
        await suggestionService.block(topic: "first topic")

        let model = TrioPromptModel(
            aiService: MockAIService(),
            suggestionService: suggestionService,
            usageService: nil,
            apiKeyValidator: { true }
        )

        let first = Task { await model.generateVariations(for: "first topic") }
        await suggestionService.waitUntilRequestStarts(for: "first topic")

        await model.generateVariations(for: "final topic")
        await suggestionService.resume(topic: "first topic")
        await first.value

        #expect(model.suggestedVariations == [
            "Final suggestion 1?",
            "Final suggestion 2?",
            "Final suggestion 3?"
        ])
    }

    @Test
    func generateVariationsFailureSurfacesErrorAndClearsSuggestions() async {
        let suggestionService = MockAISuggestionService()
        await suggestionService.setShouldFail(true)

        let model = TrioPromptModel(
            aiService: MockAIService(),
            suggestionService: suggestionService,
            usageService: nil,
            apiKeyValidator: { true }
        )
        model.suggestedVariations = ["Existing suggestion?"]

        await model.generateVariations(for: "travel memories")

        #expect(model.error?.isEmpty == false)
        #expect(model.suggestedVariations.isEmpty)
    }

    @Test
    func changingTopicAfterSuggestionFailureClearsStaleError() async {
        let suggestionService = MockAISuggestionService()
        await suggestionService.setShouldFail(true)

        let model = TrioPromptModel(
            aiService: MockAIService(),
            suggestionService: suggestionService,
            usageService: nil,
            apiKeyValidator: { true }
        )

        await model.generateVariations(for: "travel memories")
        #expect(model.error?.isEmpty == false)

        model.onIdeaTextEdited("hi")

        #expect(model.error == nil)
        #expect(model.suggestedVariations.isEmpty)
        #expect(model.isGeneratingSuggestions == false)
    }

    @Test
    func clearSuggestionsClearsStaleError() async {
        let suggestionService = MockAISuggestionService()
        await suggestionService.setShouldFail(true)

        let model = TrioPromptModel(
            aiService: MockAIService(),
            suggestionService: suggestionService,
            usageService: nil,
            apiKeyValidator: { true }
        )

        await model.generateVariations(for: "travel memories")
        #expect(model.error?.isEmpty == false)

        model.clearSuggestions()

        #expect(model.error == nil)
        #expect(model.suggestedVariations.isEmpty)
        #expect(model.selectedVariation == nil)
        #expect(model.isGeneratingSuggestions == false)
    }

    @Test
    func generateSuggestionsAppliesSuggestedCategoryWhenUserHasNotChosenOne() async {
        let suggestionService = MockAISuggestionService()
        await suggestionService.setVariations([
            "What are your 3 favorite comfort foods?",
            "Which 3 meals feel like home?",
            "What 3 snacks always improve your day?"
        ], for: "comfort foods")
        await suggestionService.setSuggestedCategoryID("Personal", for: "comfort foods")

        let model = TrioPromptModel(
            aiService: MockAIService(),
            suggestionService: suggestionService,
            usageService: nil,
            apiKeyValidator: { true }
        )

        await model.generateSuggestions(
            for: "comfort foods",
            availableCategoryIDs: ["Daily", "Personal", "Relationships"]
        )

        #expect(model.suggestedCategoryID == "Personal")
        #expect(model.selectedCategory == "Personal")
    }

    @Test
    func manualCategoryOverridePreventsAISuggestedCategoryChangingSelection() async {
        let suggestionService = MockAISuggestionService()
        await suggestionService.setSuggestedCategoryID("Personal", for: "comfort foods")

        let model = TrioPromptModel(
            aiService: MockAIService(),
            suggestionService: suggestionService,
            usageService: nil,
            apiKeyValidator: { true }
        )

        model.selectCategory("Relationships")
        await model.generateSuggestions(
            for: "comfort foods",
            availableCategoryIDs: ["Daily", "Personal", "Relationships"]
        )

        #expect(model.suggestedCategoryID == "Personal")
        #expect(model.selectedCategory == "Relationships")
    }

    @Test
    func generateMorePassesShownSuggestionsAsExclusions() async {
        let suggestionService = MockAISuggestionService()
        await suggestionService.setVariations([
            "First suggestion?",
            "Second suggestion?",
            "Third suggestion?"
        ], for: "comfort foods")

        let model = TrioPromptModel(
            aiService: MockAIService(),
            suggestionService: suggestionService,
            usageService: nil,
            apiKeyValidator: { true }
        )

        await model.generateSuggestions(
            for: "comfort foods",
            availableCategoryIDs: ["Daily", "Personal"]
        )
        await model.generateSuggestions(
            for: "comfort foods",
            availableCategoryIDs: ["Daily", "Personal"]
        )

        #expect(await suggestionService.getLastExcluding() == [
            "First suggestion?",
            "Second suggestion?",
            "Third suggestion?"
        ])
    }

    @Test
    func questionTextEditDoesNotAutomaticallyGenerateSuggestions() async {
        let suggestionService = MockAISuggestionService()
        await suggestionService.setVariations([
            "What are your 3 favorite comfort foods?",
            "Which 3 meals feel like home?",
            "What 3 snacks always improve your day?"
        ], for: "comfort foods")

        let model = TrioPromptModel(
            aiService: MockAIService(),
            suggestionService: suggestionService,
            usageService: nil,
            apiKeyValidator: { true }
        )

        model.onQuestionTextEdited(
            "comfort foods",
            availableCategoryIDs: ["Daily", "Personal"]
        )

        #expect(model.suggestedVariations.isEmpty)
        #expect(model.isGeneratingSuggestions == false)
        #expect(await suggestionService.getGenerateSuggestionsCallCount() == 0)
    }

    @Test
    func editingQuestionTextClearsLoadingForInFlightSuggestionRequest() async {
        let suggestionService = ContinuationAISuggestionService()
        await suggestionService.setResult(
            TrioQuestionSuggestionResult(
                suggestions: [
                    "What are your 3 favorite comfort foods?",
                    "Which 3 meals feel like home?",
                    "What 3 snacks always improve your day?",
                ],
                suggestedCategoryID: "Daily"
            ),
            for: "comfort foods"
        )
        await suggestionService.block(topic: "comfort foods")

        let model = TrioPromptModel(
            aiService: MockAIService(),
            suggestionService: suggestionService,
            usageService: nil,
            apiKeyValidator: { true }
        )

        let request = Task {
            await model.generateSuggestions(
                for: "comfort foods",
                availableCategoryIDs: ["Daily", "Personal"]
            )
        }
        await suggestionService.waitUntilRequestStarts(for: "comfort foods")

        model.onQuestionTextEdited(
            "comfort foods edited",
            availableCategoryIDs: ["Daily", "Personal"]
        )
        await suggestionService.resume(topic: "comfort foods")
        await request.value

        #expect(model.isGeneratingSuggestions == false)
        #expect(model.suggestedVariations.isEmpty)
    }

    @Test
    func cancelledSuggestionRequestCannotCommitDependencyResult() async {
        let suggestionService = ContinuationAISuggestionService()
        await suggestionService.setResult(
            TrioQuestionSuggestionResult(
                suggestions: [
                    "Stale suggestion one?",
                    "Stale suggestion two?",
                    "Stale suggestion three?",
                ],
                suggestedCategoryID: "Daily"
            ),
            for: "cancelled topic"
        )
        await suggestionService.block(topic: "cancelled topic")
        let model = TrioPromptModel(
            aiService: MockAIService(),
            suggestionService: suggestionService,
            usageService: nil,
            apiKeyValidator: { true }
        )

        let request = Task {
            await model.generateVariations(for: "cancelled topic")
        }
        await suggestionService.waitUntilRequestStarts(for: "cancelled topic")
        request.cancel()
        await suggestionService.resume(topic: "cancelled topic")
        await request.value

        #expect(model.suggestedVariations.isEmpty)
        #expect(model.suggestedCategoryID == nil)
        #expect(model.usageStats.dailyQueries == 0)
        #expect(model.error == nil)
        #expect(model.isGeneratingSuggestions == false)
    }

}
