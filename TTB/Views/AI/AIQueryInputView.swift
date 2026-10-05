//
//  AIQueryInputView.swift
//  TTB
//
//  Created by AI Assistant on 2025-07-18.
//

import SwiftUI

struct AIQueryInputView: View {
    @EnvironmentObject private var aiModel: AIModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedCategory: AICategory = .recommendations
    @State private var question: String = ""
    @State private var isSubmitting = false
    @State private var showingResult = false
    @State private var resultQuery: AIQuery?
    @FocusState private var isTextFieldFocused: Bool
    
    var body: some View {
        NavigationView {
            if showingResult, let result = resultQuery {
                // Show result view
                ScrollView {
                    VStack(spacing: 24) {
                        // Result header
                        resultHeaderView
                        
                        // Question display
                        questionDisplayView(result.question)
                        
                        // Response display
                        responseDisplayView(result)
                        
                        // Action buttons
                        resultActionButtonsView
                    }
                    .padding()
                }
                .navigationTitle(String(localized: "ai.input.resultTitle"))
                .navigationBarTitleDisplayMode(.large)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(String(localized: "common.done")) {
                            dismiss()
                        }
                        .fontWeight(.medium)
                    }
                }
            } else {
                // Show input view
                ScrollView {
                    VStack(spacing: 24) {
                        // Question input
                        questionInputView
                        
                        // Quick suggestions
                        quickSuggestionsView
                        
                        // Submit button
                        submitButtonView
                        
                        // Category selection
                        categorySelectionView
                        
                        // Usage limits display
                        usageLimitsView
                    }
                    .padding()
                }
                .navigationTitle(String(localized: "ai.input.newTitle"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button(String(localized: "common.cancel")) {
                            dismiss()
                        }
                    }
                    
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(String(localized: "ai.input.sendButton")) {
                            submitQuestion()
                        }
                        .disabled(!canSubmit)
                    }
                }
            }
        }
        .onAppear {
            isTextFieldFocused = true
        }
    }
    
    // MARK: - Usage Limits View
    private var usageLimitsView: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "info.circle")
                    .foregroundColor(.accentColor)
                
                Text(String(localized: "ai.input.usageTitle"))
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Spacer()
            }
            
            HStack(spacing: 20) {
                limitStatusView(
                    title: String(localized: "ai.input.today"),
                    current: aiModel.usageStats.dailyQueries,
                    limit: aiModel.dailyLimit
                )
                
                limitStatusView(
                    title: String(localized: "ai.input.week"),
                    current: aiModel.usageStats.weeklyQueries,
                    limit: aiModel.weeklyLimit
                )
                
                limitStatusView(
                    title: String(localized: "ai.input.month"),
                    current: aiModel.usageStats.monthlyQueries,
                    limit: aiModel.monthlyLimit
                )
            }
            
            if let statusMessage = aiModel.serviceStatusMessage {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.top, 8)
            }
        }
        .padding()
        .background(Color.theme.secondaryBackground)
        .cornerRadius(12)
    }
    
    private func limitStatusView(title: String, current: Int, limit: Int) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            
            Text("\(current)/\(limit)")
                .font(.body)
                .fontWeight(.medium)
                .foregroundColor(current >= limit ? .red : .primary)
            
            ProgressView(value: Double(current), total: Double(limit))
                .progressViewStyle(LinearProgressViewStyle())
                .scaleEffect(x: 1, y: 0.6)
        }
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - Category Selection View
    private var categorySelectionView: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 12) {
                Text(String(localized: "ai.input.categoryTitle"))
                    .font(.headline)
                    .foregroundColor(.primary)
                Text(String(localized: "ai.input.categoryHint"))
                    .font(.footnote)
                    .foregroundColor(.secondary)
                
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 12) {
                    ForEach(AICategory.allCases) { category in
                        categoryButton(category: category)
                    }
                }
            }
        }
    }
    
    private func categoryButton(category: AICategory) -> some View {
        Button(action: { selectedCategory = category }) {
            VStack(spacing: 8) {
                Image(systemName: category.icon)
                    .font(.title2)
                    .foregroundColor(selectedCategory == category ? .white : .accentColor)
                
                Text(category.localizedName)
                    .font(.caption)
                    .foregroundColor(selectedCategory == category ? .white : .primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(selectedCategory == category ? Color.accentColor : Color.theme.secondaryBackground)
            .cornerRadius(12)
        }
    }
    
    // MARK: - Question Input View
    private var questionInputView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "ai.input.questionTitle"))
                .font(.headline)
                .foregroundColor(.primary)
            
            VStack(alignment: .leading, spacing: 8) {
                TextField(String(localized: "ai.input.questionPlaceholder"), text: $question, axis: .vertical)
                    .textFieldStyle(PlainTextFieldStyle())
                    .focused($isTextFieldFocused)
                    .lineLimit(3...6)
                    .padding()
                    .background(Color.theme.secondaryBackground)
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isTextFieldFocused ? Color.accentColor : Color.clear, lineWidth: 2)
                    )
                
                HStack {
                    Text("\(question.count)/500")
                        .font(.caption)
                        .foregroundColor(question.count > 500 ? .red : .secondary)
                    
                    Spacer()
                    
                    if !question.isEmpty {
                        Button(action: { question = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Quick Suggestions View
    private var quickSuggestionsView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "ai.input.quickSuggestionsTitle"))
                .font(.headline)
                .foregroundColor(.primary)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(suggestions(for: selectedCategory), id: \.self) { suggestion in
                        Button(action: { question = suggestion }) {
                            Text(suggestion)
                                .font(.body)
                                .foregroundColor(.primary)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(Color.theme.secondaryBackground)
                                .cornerRadius(20)
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
    }
    
    // MARK: - Submit Button View
    private var submitButtonView: some View {
        Button(action: submitQuestion) {
            HStack {
                if isSubmitting {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle())
                        .scaleEffect(0.8)
                        .foregroundColor(.white)
                } else {
                    Image(systemName: "paperplane.fill")
                        .font(.title2)
                }
                
                Text(isSubmitting ? String(localized: "ai.input.sendLoading") : String(localized: "ai.input.sendButton"))
                    .font(.headline)
                    .fontWeight(.medium)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(canSubmit ? Color.accentColor : Color.secondary.opacity(0.3))
            .foregroundColor(.white)
            .cornerRadius(12)
            .scaleEffect(canSubmit ? 1.0 : 0.95)
            .animation(.easeInOut(duration: 0.2), value: canSubmit)
            .animation(.easeInOut(duration: 0.2), value: isSubmitting)
        }
        .disabled(!canSubmit)
        .accessibilityLabel(isSubmitting ? String(localized: "ai.input.sendLoading") : String(localized: "ai.input.sendA11yLabel"))
        .accessibilityHint(canSubmit ? String(localized: "ai.input.sendA11yHint") : String(localized: "ai.input.sendA11yHintDisabled"))
    }
    
    // MARK: - Helper Methods
    private var canSubmit: Bool {
        !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        question.count <= 500 &&
        aiModel.isServiceAvailable &&
        !isSubmitting
    }
    
    private func submitQuestion() {
        guard canSubmit else { return }
        
        isSubmitting = true
        let trimmedQuestion = question.trimmingCharacters(in: .whitespacesAndNewlines)
        
        Task {
            await aiModel.askQuestion(trimmedQuestion, category: selectedCategory)
            
            await MainActor.run {
                isSubmitting = false
                // Show result instead of dismissing
                if let latestQuery = aiModel.recentQueries.first {
                    resultQuery = latestQuery
                    showingResult = true
                }
            }
        }
    }
    
    private func suggestions(for category: AICategory) -> [String] {
        switch category {
        case .recommendations:
            return [
                localizedSuggestion(tr: "Bugün ne yapmalıyım?", en: "What should I do today?"),
                localizedSuggestion(tr: "Yeni bir hobi öner", en: "Recommend a new hobby"),
                localizedSuggestion(tr: "Kitap tavsiyesi ver", en: "Recommend a book"),
                localizedSuggestion(tr: "Film önerisi istiyorum", en: "I want a movie recommendation")
            ]
        case .advice:
            return [
                localizedSuggestion(tr: "Karar vermekte zorlanıyorum", en: "I'm having trouble making a decision"),
                localizedSuggestion(tr: "Motivasyon arıyorum", en: "I'm looking for motivation"),
                localizedSuggestion(tr: "Stresle nasıl başa çıkarım?", en: "How do I deal with stress?"),
                localizedSuggestion(tr: "Zaman yönetimi önerileri", en: "Time management tips")
            ]
        case .learning:
            return [
                localizedSuggestion(tr: "Yeni bir beceri öğrenmek istiyorum", en: "I want to learn a new skill"),
                localizedSuggestion(tr: "Hangi programlama dili öğrenmeliyim?", en: "Which programming language should I learn?"),
                localizedSuggestion(tr: "Dil öğrenme stratejileri", en: "Language learning strategies"),
                localizedSuggestion(tr: "Online kurs önerileri", en: "Online course recommendations")
            ]
        case .travel:
            return [
                localizedSuggestion(tr: "Hafta sonu gezisi öner", en: "Recommend a weekend trip"),
                localizedSuggestion(tr: "Türkiye'de gezilecek yerler", en: "Places to visit in Turkey"),
                localizedSuggestion(tr: "Seyahat planı nasıl yapılır?", en: "How do I plan a trip?"),
                localizedSuggestion(tr: "Bütçe dostu tatil önerileri", en: "Budget-friendly vacation ideas")
            ]
        case .productivity:
            return [
                localizedSuggestion(tr: "Daha verimli nasıl olurum?", en: "How can I be more productive?"),
                localizedSuggestion(tr: "Günlük rutin önerileri", en: "Daily routine ideas"),
                localizedSuggestion(tr: "Odaklanma teknikleri", en: "Focus techniques"),
                localizedSuggestion(tr: "Hedef belirleme stratejileri", en: "Goal-setting strategies")
            ]
        case .entertainment:
            return [
                localizedSuggestion(tr: "Eğlenceli aktivite öner", en: "Suggest a fun activity"),
                localizedSuggestion(tr: "Ev partisi fikirleri", en: "House party ideas"),
                localizedSuggestion(tr: "Yaratıcı projeler", en: "Creative projects"),
                localizedSuggestion(tr: "Oyun önerileri", en: "Game recommendations")
            ]
        case .creativity:
            return [
                localizedSuggestion(tr: "Yaratıcı bir proje fikri öner", en: "Suggest a creative project idea"),
                localizedSuggestion(tr: "Sanatsal hobi önerileri", en: "Artistic hobby ideas"),
                localizedSuggestion(tr: "Yeni fikirler nasıl bulabilirim?", en: "How can I come up with new ideas?"),
                localizedSuggestion(tr: "Yaratıcılığımı nasıl geliştirebilirim?", en: "How can I improve my creativity?")
            ]
        case .health:
            return [
                localizedSuggestion(tr: "Sağlıklı yaşam tavsiyeleri", en: "Healthy living tips"),
                localizedSuggestion(tr: "Evde yapılacak egzersizler", en: "Home workouts"),
                localizedSuggestion(tr: "Beslenme önerileri", en: "Nutrition tips"),
                localizedSuggestion(tr: "Mental sağlık için ipuçları", en: "Mental health tips")
            ]
        case .career:
            return [
                localizedSuggestion(tr: "Kariyer gelişimi stratejileri", en: "Career growth strategies"),
                localizedSuggestion(tr: "İş arama tavsiyeleri", en: "Job search tips"),
                localizedSuggestion(tr: "Mesleki becerilerimi nasıl geliştirebilirim?", en: "How can I improve my professional skills?"),
                localizedSuggestion(tr: "Profesyonel ağ kurma ipuçları", en: "Professional networking tips")
            ]
        case .personal:
            return [
                localizedSuggestion(tr: "Kendimi nasıl geliştirebilirim?", en: "How can I improve myself?"),
                localizedSuggestion(tr: "Özgüvenimi artırmak için öneriler", en: "Ideas to boost my confidence"),
                localizedSuggestion(tr: "Daha iyi alışkanlıklar edinme yolları", en: "Ways to build better habits"),
                localizedSuggestion(tr: "Kişisel gelişim için kaynaklar", en: "Resources for personal growth")
            ]
        case .other:
            return [
                localizedSuggestion(tr: "Genel tavsiye ver", en: "Give general advice"),
                localizedSuggestion(tr: "Rastgele bir konu hakkında bilgi", en: "Tell me about a random topic"),
                localizedSuggestion(tr: "İlginç bir gerçek paylaş", en: "Share an interesting fact"),
                localizedSuggestion(tr: "Sohbet edelim", en: "Let's chat")
            ]
        }
    }
    
    // MARK: - Result Views
    private var resultHeaderView: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundColor(.green)
                
                Text(String(localized: "ai.input.resultReadyTitle"))
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                
                Spacer()
            }
            
            Text(String(localized: "ai.input.resultReadyBody"))
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.leading)
        }
        .padding()
        .background(Color.green.opacity(0.1))
        .cornerRadius(12)
    }
    
    private func questionDisplayView(_ questionText: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(String(localized: "ai.input.questionLabel"))
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                
                Spacer()
                
                HStack(spacing: 4) {
                    Image(systemName: selectedCategory.icon)
                        .font(.caption)
                        .foregroundColor(.accentColor)
                    
                    Text(selectedCategory.localizedName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Text(questionText)
                .font(.body)
                .foregroundColor(.primary)
                .lineSpacing(4)
                .textSelection(.enabled)
        }
        .padding()
        .background(Color.theme.secondaryBackground)
        .cornerRadius(12)
    }
    
    private func responseDisplayView(_ query: AIQuery) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(String(localized: "ai.input.responsesLabel"))
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                
                Spacer()
                
                if query.isLoading {
                    HStack(spacing: 4) {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text(String(localized: "ai.input.preparing"))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } else if query.isComplete {
                    Text("3/3")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.green)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.green.opacity(0.1))
                        .cornerRadius(8)
                }
            }
            
            if query.isLoading {
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.2)
                    
                    Text(String(localized: "ai.input.thinking"))
                        .font(.body)
                        .foregroundColor(.secondary)
                }
                .frame(height: 100)
            } else if let error = query.error {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 40))
                        .foregroundColor(.red)
                    
                    Text(String(localized: "ai.input.errorTitle"))
                        .font(.headline)
                        .foregroundColor(.red)
                    
                    Text(error)
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
            } else if query.isComplete {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(Array(query.responses.enumerated()), id: \.offset) { index, response in
                        HStack(alignment: .top, spacing: 12) {
                            // Number Badge
                            Text("\(index + 1)")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                                .frame(width: 24, height: 24)
                                .background(Color.accentColor)
                                .clipShape(Circle())
                            
                            // Response Text
                            Text(response)
                                .font(.body)
                                .foregroundColor(.primary)
                                .lineSpacing(4)
                                .textSelection(.enabled)
                        }
                        .padding()
                        .background(Color.theme.background)
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.accentColor.opacity(0.2), lineWidth: 1)
                        )
                    }
                }
            }
        }
        .padding()
        .background(Color.theme.secondaryBackground)
        .cornerRadius(12)
    }
    
    private var resultActionButtonsView: some View {
        VStack(spacing: 12) {
            if let query = resultQuery, query.isComplete {
                HStack(spacing: 12) {
                    Button(action: {
                        Task {
                            await aiModel.saveQuery(query)
                        }
                    }) {
                        HStack {
                            Image(systemName: "bookmark")
                            Text(String(localized: "common.save"))
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    
                    Button(action: {
                        // Share functionality could be added here
                        let pasteboard = UIPasteboard.general
                        if let query = resultQuery {
                            let shareText = "\(query.question)\n\nCevaplar:\n\(query.responses.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n"))"
                            pasteboard.string = shareText
                        }
                    }) {
                        HStack {
                            Image(systemName: "square.and.arrow.up")
                            Text(String(localized: "common.share"))
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.theme.secondaryBackground)
                        .foregroundColor(.primary)
                        .cornerRadius(12)
                    }
                }
            }
            
            Button(action: {
                // Reset to new question
                showingResult = false
                resultQuery = nil
                question = ""
                selectedCategory = .recommendations
                isTextFieldFocused = true
            }) {
                HStack {
                    Image(systemName: "plus.message")
                    Text(String(localized: "ai.input.newQuestion"))
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.theme.secondaryBackground)
                .foregroundColor(.primary)
                .cornerRadius(12)
            }
        }
    }
}

// MARK: - Preview
#if DEBUG
struct AIQueryInputView_Previews: PreviewProvider {
    // MARK: - Individual Preview Components
    static var normalState: some View {
        AIQueryInputView()
            .environmentObject(AIModel())
    }
    
    static var limitReachedState: some View {
        AIQueryInputView()
            .environmentObject({
                let model = AIModel()
                // Create a new AIUsageStats instance with desired values
                let stats = AIUsageStats(
                    dailyQueries: 10,
                    weeklyQueries: model.usageStats.weeklyQueries,
                    monthlyQueries: model.usageStats.monthlyQueries,
                    totalQueries: model.usageStats.totalQueries,
                    lastQueryDate: model.usageStats.lastQueryDate,
                    favoriteCategory: model.usageStats.favoriteCategory,
                    lastResetDate: model.usageStats.lastResetDate
                )
                model.setUsageStatsForTesting(stats)
                return model
            }())
    }
    
    static var nearLimitState: some View {
        AIQueryInputView()
            .environmentObject({
                let model = AIModel()
                // Create a new AIUsageStats instance with desired values
                let stats = AIUsageStats(
                    dailyQueries: 8,
                    weeklyQueries: 45,
                    monthlyQueries: model.usageStats.monthlyQueries,
                    totalQueries: model.usageStats.totalQueries,
                    lastQueryDate: model.usageStats.lastQueryDate,
                    favoriteCategory: model.usageStats.favoriteCategory,
                    lastResetDate: model.usageStats.lastResetDate
                )
                model.setUsageStatsForTesting(stats)
                return model
            }())
    }
    
    static var previews: some View {
        Group {
            normalState
                .previewDisplayName("Normal State")
            
            limitReachedState
                .previewDisplayName("Limit Reached")
            
            nearLimitState
                .previewDisplayName("Near Limit")
            
            normalState
                .preferredColorScheme(.dark)
                .previewDisplayName("Dark Mode")
            
            normalState
                .environment(\.sizeCategory, .accessibilityExtraExtraExtraLarge)
                .previewDisplayName("Large Text")
            
            normalState
                .previewDevice("iPhone SE (3rd generation)")
                .previewDisplayName("Compact Screen")
        }
    }
}

#endif

private func localizedSuggestion(tr: String, en: String) -> String {
    AppLocalization.prefersEnglish ? en : tr
}
