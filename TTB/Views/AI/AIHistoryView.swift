//
//  AIHistoryView.swift
//  TTB
//
//  Created by AI Assistant on 2025-07-18.
//

import SwiftUI

struct AIHistoryView: View {
    @EnvironmentObject private var aiModel: AIModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedCategory: AICategory?
    @State private var searchText = ""
    @State private var showingDeleteConfirmation = false
    @State private var queryToDelete: AIQuery?
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Search and Filter Section
                searchAndFilterSection
                
                // History List
                if filteredQueries.isEmpty {
                    emptyStateView
            } else {
                historyListView
            }
        }
            .navigationTitle(String(localized: "ai.history.title"))
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(String(localized: "common.close")) {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button(action: {
                            Task {
                                await aiModel.clearHistory()
                            }
                        }) {
                            Label(String(localized: "ai.history.clearHistory"), systemImage: "trash")
                        }
                        
                        Button(action: {
                            Task {
                                await aiModel.loadQueries()
                            }
                        }) {
                            Label(String(localized: "common.refresh"), systemImage: "arrow.clockwise")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .searchable(text: $searchText, prompt: String(localized: "ai.history.searchPlaceholder"))
        .alert(String(localized: "ai.history.deleteTitle"), isPresented: $showingDeleteConfirmation) {
            Button(String(localized: "common.cancel"), role: .cancel) {
                queryToDelete = nil
            }
            Button(String(localized: "common.delete"), role: .destructive) {
                if let query = queryToDelete {
                    Task {
                        await aiModel.deleteQuery(query)
                    }
                    queryToDelete = nil
                }
            }
        } message: {
            Text("Bu soruyu kalıcı olarak silmek istediğinize emin misiniz?")
        }
    }
    
    // MARK: - Search and Filter Section
    private var searchAndFilterSection: some View {
        VStack(spacing: 12) {
            // Category Filter
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    // All Categories Button
                    Button(action: {
                        selectedCategory = nil
                        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                        impactFeedback.impactOccurred()
                    }) {
                        Text(String(localized: "ai.history.allCategories"))
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(selectedCategory == nil ? .white : .primary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(selectedCategory == nil ? Color.accentColor : Color.theme.secondaryBackground)
                            .cornerRadius(20)
                    }
                    .accessibilityLabel(String(localized: "ai.history.allCategoriesAccessibilityLabel"))
                    .accessibilityHint(String(localized: "ai.history.allCategoriesAccessibilityHint"))
                    .accessibilityAddTraits(selectedCategory == nil ? [.isSelected] : [])
                    
                    // Category Buttons
                    ForEach(AICategory.allCases) { category in
                        Button(action: {
                            selectedCategory = category
                            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                            impactFeedback.impactOccurred()
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: category.icon)
                                    .font(.caption)
                                
                                Text(category.localizedName)
                                    .font(.caption)
                                    .fontWeight(.medium)
                            }
                            .foregroundColor(selectedCategory == category ? .white : .primary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(selectedCategory == category ? Color.accentColor : Color.theme.secondaryBackground)
                            .cornerRadius(20)
                        }
                        .accessibilityLabel(category.localizedName)
                        .accessibilityHint(selectedCategory == category
                            ? String(localized: "ai.history.categorySelectedHint")
                            : String(localized: "ai.history.categoryAccessibilityHint"))
                        .accessibilityAddTraits(selectedCategory == category ? [.isSelected] : [])
                    }
                }
                .padding(.horizontal)
            }
            
            // Stats Summary
            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "ai.history.totalQueries"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("\(aiModel.queries.count)")
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                }
                
                Divider()
                    .frame(height: 30)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "ai.history.savedQueries"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("\(aiModel.queries.filter { $0.isSaved }.count)")
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                }
                
                Divider()
                    .frame(height: 30)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "ai.history.thisMonth"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("\(aiModel.usageStats.monthlyQueries)")
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                }
                
                Spacer()
            }
            .padding(.horizontal)
        }
        .padding(.vertical, 12)
        .background(Color.theme.background)
    }
    
    // MARK: - History List View
    private var historyListView: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(filteredQueries) { query in
                    AIHistoryCard(query: query) {
                        queryToDelete = query
                        showingDeleteConfirmation = true
                    }
                    .environmentObject(aiModel)
                }
            }
            .padding()
        }
    }
    
    // MARK: - Empty State View
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "clock.badge.questionmark")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            
            Text(String(localized: "ai.history.emptyTitle"))
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
            
            Text(String(localized: "ai.history.emptyBody"))
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            Button(action: { dismiss() }) {
                Text(String(localized: "ai.history.newQuestion"))
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Color.accentColor)
                    .cornerRadius(12)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
    
    // MARK: - Computed Properties
    private var filteredQueries: [AIQuery] {
        var queries = aiModel.queries
        
        // Filter by category
        if let selectedCategory = selectedCategory {
            queries = queries.filter { $0.category == selectedCategory }
        }
        
        // Filter by search text
        if !searchText.isEmpty {
            queries = queries.filter { 
                $0.question.localizedCaseInsensitiveContains(searchText) ||
                $0.responses.joined(separator: " ").localizedCaseInsensitiveContains(searchText)
            }
        }
        
        return queries.sorted { $0.timestamp > $1.timestamp }
    }
}

// MARK: - AI History Card
struct AIHistoryCard: View {
    let query: AIQuery
    let onDelete: () -> Void
    @EnvironmentObject private var aiModel: AIModel
    @State private var isExpanded = false
    @State private var showingShareSheet = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                // Category Icon
                Image(systemName: query.category.icon)
                    .font(.body)
                    .foregroundColor(.accentColor)
                
                // Category and Date
                VStack(alignment: .leading, spacing: 2) {
                    Text(query.category.localizedName)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                    
                    Text(query.formattedTimestamp)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Status Indicator
                if query.isSaved {
                    Image(systemName: "bookmark.fill")
                        .font(.caption)
                        .foregroundColor(.accentColor)
                }
                
                if query.isLoading {
                    ProgressView()
                        .scaleEffect(0.8)
                } else if query.error != nil {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
            
            // Question
            Text(query.question)
                .font(.body)
                .fontWeight(.medium)
                .foregroundColor(.primary)
                .lineLimit(isExpanded ? nil : 2)
            
            // Responses
            if query.isComplete {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(query.responses.enumerated()), id: \.offset) { index, response in
                        HStack(alignment: .top, spacing: 8) {
                            Text("\(index + 1)")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(.accentColor)
                                .frame(width: 16, alignment: .leading)
                            
                            Text(response)
                                .font(.body)
                                .foregroundColor(.secondary)
                                .lineLimit(isExpanded ? nil : 2)
                        }
                    }
            }
            .padding(.top, 4)
        } else if let error = query.error {
            Text(String(format: String(localized: "ai.history.errorPrefix"), locale: AppLocalization.currentLocale, error))
                .font(.caption)
                .foregroundColor(.red)
                .padding(.top, 4)
        }
        
        // Actions
        HStack {
            Button(action: { isExpanded.toggle() }) {
                Text(isExpanded ? String(localized: "ai.history.collapse") : String(localized: "ai.history.expand"))
                    .font(.caption)
                    .foregroundColor(.accentColor)
            }
                
                Spacer()
                
                if query.isComplete {
                    Button(action: { showingShareSheet = true }) {
                        HStack(spacing: 4) {
                            Image(systemName: "square.and.arrow.up")
                            Text(String(localized: "ai.history.share"))
                        }
                        .font(.caption)
                        .foregroundColor(.accentColor)
                    }
                    
                    Button(action: {
                        Task {
                            await aiModel.saveQuery(query)
                        }
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: query.isSaved ? "bookmark.fill" : "bookmark")
                            Text(query.isSaved ? String(localized: "ai.history.saved") : String(localized: "ai.history.save"))
                        }
                        .font(.caption)
                        .foregroundColor(.accentColor)
                    }
                    .disabled(query.isSaved)
                }
                
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
        }
        .padding()
        .background(Color.theme.secondaryBackground)
        .cornerRadius(12)
        .shadow(radius: 1)
        .sheet(isPresented: $showingShareSheet) {
            AIShareSheet(query: query)
        }
    }
}

// MARK: - Preview
#if DEBUG
struct AIHistoryView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            // Normal History with Data
            AIHistoryView()
                .environmentObject(AIModel.sample)
                .previewDisplayName("Normal History")
            
            // Empty History
            AIHistoryView()
                .environmentObject({
                    let model = AIModel()
                    // Empty model with no queries
                    return model
                }())
                .previewDisplayName("Empty History")
            
            // History with Loading State
            AIHistoryView()
                .environmentObject({
                    let model = AIModel()
                    model.setQueriesForTesting(AIQuery.sampleQueries)
                    model.setLoadingStateForTesting(true)
                    return model
                }())
                .previewDisplayName("Loading History")
            
            // History with Error State
            AIHistoryView()
                .environmentObject({
                    let model = AIModel()
                    model.setQueriesForTesting(AIQuery.sampleQueries)
                    model.setErrorForTesting("Geçmiş yüklenirken bir hata oluştu")
                    return model
                }())
                .previewDisplayName("Error History")
            
            // History with Many Queries
            AIHistoryView()
                .environmentObject({
                    let model = AIModel()
                    // Add more sample queries
                    let additionalQueries = [
                        AIQuery(
                            question: "Yazılım geliştirme için en iyi pratikler nelerdir?",
                            responses: [
                                "Clean Code prensiplerine uygun kod yazın",
                                "Test-driven development (TDD) yaklaşımını benimseyin",
                                "Sürekli öğrenme ve kendini geliştirme alışkanlığı edinin"
                            ],
                            category: .learning,
                            isSaved: true
                        ),
                        AIQuery(
                            question: "Ev egzersizleri için öneriler",
                            responses: [
                                "Günde 30 dakika cardio egzersizi yapın",
                                "Kuvvet antrenmanları için vücut ağırlığı egzersizleri",
                                "Yoga ve stretching ile esnekliğinizi artırın"
                            ],
                            category: .health,
                            isSaved: false
                        ),
                        AIQuery(
                            question: "Kreatif yazım teknikleri",
                            responses: [
                                "Serbest yazım ile fikirlerinizi akış halinde yazın",
                                "Karakter geliştirme için detaylı profiller oluşturun",
                                "Günlük yazım alışkanlığı edinin"
                            ],
                            category: .creativity,
                            isSaved: true
                        )
                    ]
                    model.setQueriesForTesting(AIQuery.sampleQueries + additionalQueries)
                    return model
                }())
                .previewDisplayName("Many Queries")
            
            // Dark Mode
            AIHistoryView()
                .environmentObject(AIModel.sample)
                .preferredColorScheme(.dark)
                .previewDisplayName("Dark Mode")
            
            // Large Text Size
            AIHistoryView()
                .environmentObject(AIModel.sample)
                .environment(\.sizeCategory, .accessibilityExtraExtraExtraLarge)
                .previewDisplayName("Large Text")
        }
    }
}
#endif
