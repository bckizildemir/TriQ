import SwiftUI

struct TrioPromptComposerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.toastCenter) private var toastCenter
    @EnvironmentObject private var categoryModel: CategoryModel
    @ObservedObject var model: TrioPromptModel
    let onSubmit: () async -> Bool

    @FocusState private var isQuestionFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    introBlock
                    questionInput
                    suggestionSection
                    aiAction
                    categoryPicker
                    errorMessage
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
            }
            .background(Color.theme.background)
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(String(localized: "ai.trioComposer.sheetTitle"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel(String(localized: "common.cancel"))
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        submit()
                    } label: {
                        if model.isPublishing {
                            ProgressView()
                        } else {
                            Image(systemName: "checkmark")
                        }
                    }
                    .disabled(!model.canPublish)
                    .accessibilityIdentifier("trio-publish-button")
                    .accessibilityLabel(String(localized: "ai.trioComposer.submitForReview"))
                    .accessibilityValue(model.canPublish ? "ready" : "blocked")
                }
            }
            .onAppear {
                model.clearMessages()
                if !categoryModel.activeCategories.contains(where: { $0.id == model.selectedCategory }),
                   let firstCategory = categoryModel.activeCategories.first {
                    model.selectedCategory = firstCategory.id
                }
            }
            .onChange(of: model.draftQuestion) { _, newValue in
                model.onQuestionTextEdited(
                    newValue,
                    availableCategoryIDs: activeCategoryIDs
                )
            }
        }
    }

    private var activeCategoryIDs: [String] {
        categoryModel.activeCategories.map(\.id)
    }

    private var introBlock: some View {
        Text(String(localized: "ai.trioComposer.sheetDescription"))
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var questionInput: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Spacer()

                Text("\(model.questionCharacterCount)/\(model.maximumQuestionLength)")
                    .font(.caption)
                    .foregroundStyle(model.trimmedDraft.count > model.maximumQuestionLength ? .red : .secondary)
                    .monospacedDigit()
            }

            TextField(
                String(localized: "ai.trioComposer.questionPlaceholder"),
                text: $model.draftQuestion,
                axis: .vertical
            )
            .focused($isQuestionFocused)
            .lineLimit(5...8)
            .textInputAutocapitalization(.sentences)
            .padding(14)
            .frame(minHeight: 140, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color.theme.secondaryBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(Color.accentColor.opacity(isQuestionFocused ? 0.45 : 0.16), lineWidth: 1.25)
                    )
            )
            .accessibilityIdentifier("trio-draft-field")
            .accessibilityLabel(String(localized: "ai.trioComposer.questionInput"))

            if let validationMessage = model.questionValidationMessage {
                Text(validationMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("trio-validation-error")
            }
        }
    }

    private var canGenerateIdeas: Bool {
        model.isAIAvailable
            && model.trimmedDraft.split { $0.isWhitespace || $0.isNewline }.count >= model.minimumWordsForAutoSuggestions
            && !model.isGeneratingSuggestions
            && !model.hasReachedDailyLimit
    }

    private var aiAction: some View {
        Button {
            isQuestionFocused = false
            Task {
                await model.generateSuggestions(
                    for: model.trimmedDraft,
                    availableCategoryIDs: activeCategoryIDs
                )
            }
            triggerHapticFeedback(style: .medium)
        } label: {
            Label(
                model.isGeneratingSuggestions
                    ? String(localized: "ai.trioComposer.generatingIdeas")
                    : (model.suggestedVariations.isEmpty
                        ? String(localized: "ai.trioComposer.generateIdeas")
                        : String(localized: "ai.trioComposer.generateMoreIdeas")),
                systemImage: "sparkles"
            )
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .disabled(!canGenerateIdeas)
        .accessibilityIdentifier("trio-generate-ideas-button")
        .accessibilityHint(String(localized: "ai.trioComposer.generateIdeasHint"))
    }

    @ViewBuilder
    private var suggestionSection: some View {
        if model.isAIAvailable
            && (!model.suggestedVariations.isEmpty || model.isGeneratingSuggestions)
        {
            SuggestionChipsContainer(
                suggestions: model.suggestedVariations,
                selectedSuggestion: model.selectedVariation,
                isLoading: model.isGeneratingSuggestions,
                isSelectionDisabled: model.isGeneratingSuggestions,
                onSelect: { variation in
                    model.selectVariation(variation)
                    triggerHapticFeedback(style: .medium)
                }
            )
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color.theme.secondaryBackground)
            )
        }
    }

    private var categoryPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "ai.trioComposer.category"))
                .font(.headline)

            if let suggestedCategory = suggestedCategory {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.caption)
                    Text(
                        String(
                            format: String(localized: "ai.trioComposer.suggestedCategory"),
                            locale: AppLocalization.currentLocale,
                            suggestedCategory.displayName
                        )
                    )
                    .font(.footnote.weight(.medium))
                }
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("trio-suggested-category")
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(categoryModel.activeCategories) { category in
                        Button {
                            model.selectCategory(category.id)
                            triggerHapticFeedback(style: .light)
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: category.iconSystemName)
                                    .font(.caption)
                                Text(category.displayName)
                                    .font(.footnote.weight(.medium))
                                if model.selectedCategory == category.id {
                                    Image(systemName: "checkmark")
                                        .font(.caption.bold())
                                }
                            }
                            .foregroundStyle(model.selectedCategory == category.id ? .white : .primary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .frame(minHeight: 40)
                            .background(
                                Capsule()
                                    .fill(model.selectedCategory == category.id ? Color.accentColor : Color.theme.secondaryBackground)
                            )
                            .overlay(
                                Capsule()
                                    .stroke(
                                        model.selectedCategory == category.id ? Color.clear : Color.theme.border.opacity(0.45),
                                        lineWidth: 1
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(category.displayName)
                        .accessibilityHint(model.selectedCategory == category.id ? "Selected" : "Double tap to select")
                        .accessibilityAddTraits(model.selectedCategory == category.id ? [.isButton, .isSelected] : .isButton)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private var suggestedCategory: Category? {
        guard let suggestedCategoryID = model.suggestedCategoryID else { return nil }
        return categoryModel.activeCategories.first(where: { $0.id == suggestedCategoryID })
    }

    @ViewBuilder
    private var errorMessage: some View {
        if let error = model.error {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .font(.footnote)
                .foregroundStyle(.red)
                .accessibilityIdentifier("trio-publish-error")
        }
    }

    private func submit() {
        isQuestionFocused = false

        Task {
            let didSubmit = await onSubmit()
            guard didSubmit else { return }
            toastCenter.showSuccess(
                title: model.successMessage ?? String(localized: "ai.trio.submitSuccess"),
                subtitle: String(localized: "ai.trio.submitSuccessMessage"),
                accessibilityIdentifier: "trio-publish-success-toast"
            )
            try? await Task.sleep(nanoseconds: 900_000_000)
            dismiss()
        }
    }

    private func triggerHapticFeedback(style: UIImpactFeedbackGenerator.FeedbackStyle) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.impactOccurred()
    }
}

#Preview {
    TrioPromptComposerView(
        model: TrioPromptModel(aiService: MockPreviewAIService(), usageService: nil),
        onSubmit: { true }
    )
    .environmentObject(CategoryModel(localCategories: Category.defaultCategories))
}

private actor MockPreviewAIService: AIServiceProtocol {
    func askQuestion(_ question: String, category: AICategory) async throws -> [String] { [] }
    func suggestAnswers(for question: String) async throws -> [String] { [] }
    func suggestQuickAnswers(
        for question: String,
        category: String,
        excluding: [String],
        languageName: String?,
        limit: Int
    ) async throws -> [String] { [] }
    func generateQuestionPrompt(from idea: String, category: String) async throws -> String { idea }
    func generateQuestionVariations(from topic: String, count: Int) async throws -> [String] {
        Array([
            "What are your 3 favorite comfort foods?",
            "Which 3 foods feel like home?",
            "What 3 meals would you always repeat?"
        ].prefix(count))
    }
    func generateTrioQuestionSuggestions(
        from topic: String,
        count: Int,
        excluding: [String],
        availableCategoryIDs: [String]
    ) async throws -> TrioQuestionSuggestionResult {
        _ = topic
        _ = excluding
        return TrioQuestionSuggestionResult(
            suggestions: Array([
                "What are your 3 favorite comfort foods?",
                "Which 3 foods feel like home?",
                "What 3 meals would you always repeat?"
            ].prefix(count)),
            suggestedCategoryID: availableCategoryIDs.first ?? "Daily"
        )
    }
}
