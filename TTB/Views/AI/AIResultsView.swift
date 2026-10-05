//
//  AIResultsView.swift
//  TTB
//
//  Created by AI Assistant on 2025-07-18.
//

import SwiftUI

struct AIResultsView: View {
    let queries: [AIQuery]
    @EnvironmentObject private var aiModel: AIModel
    @State private var selectedQuery: AIQuery?
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                ForEach(queries.prefix(10)) { query in
                    AIQueryCard(query: query)
                        .environmentObject(aiModel)
                        .onTapGesture {
                            selectedQuery = query
                        }
                }
                
                if queries.count > 10 {
                    Button(String(localized: "common.showMore")) {
                        // TODO: Load more queries
                    }
                    .foregroundColor(.accentColor)
                    .padding()
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .sheet(item: $selectedQuery) { query in
            AIQueryDetailView(query: query)
                .environmentObject(aiModel)
        }
    }
}


// MARK: - AI History Row
struct AIHistoryRow: View {
    let query: AIQuery
    @EnvironmentObject private var aiModel: AIModel
    @State private var showingDetail = false
    
    var body: some View {
        Button(action: { showingDetail = true }) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    HStack(spacing: 4) {
                        Image(systemName: query.category.icon)
                            .foregroundColor(.accentColor)
                            .font(.caption)
                        
                        Text(query.category.localizedName)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Text(query.formattedTimestamp)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if query.isComplete {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.caption)
                    } else if query.error != nil {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                }
                
                Text(query.question)
                    .font(.body)
                    .foregroundColor(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                
                if query.isComplete {
                    Text(String(format: String(localized: "ai.results.responsesCount"), locale: AppLocalization.currentLocale, query.responses.count))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
        .sheet(isPresented: $showingDetail) {
            AIQueryDetailView(query: query)
                .environmentObject(aiModel)
        }
    }
}

// MARK: - Preview
struct AIResultsView_Previews: PreviewProvider {
    // MARK: - Individual Preview Components
    static var normalResults: some View {
        AIResultsView(queries: AIQuery.sampleQueries)
            .environmentObject(AIModel.sample)
    }
    
    static var emptyResults: some View {
        AIResultsView(queries: [])
            .environmentObject(AIModel.sample)
    }
    
    static var fewResults: some View {
        AIResultsView(queries: Array(AIQuery.sampleQueries.prefix(3)))
            .environmentObject(AIModel.sample)
    }
    
    static var mixedStates: some View {
        AIResultsView(queries: [
            AIQuery.sampleQueries[0], // Complete
            AIQuery(
                question: "Yükleniyor...",
                responses: [],
                timestamp: Date(),
                category: .personal,
                isSaved: false,
                isLoading: true,
                error: nil
            ),
            AIQuery(
                question: "Hata durumu",
                responses: [],
                timestamp: Date(),
                category: .career,
                isSaved: false,
                isLoading: false,
                error: "Ağ hatası"
            )
        ])
        .environmentObject(AIModel.sample)
    }
    
    static var previews: some View {
        Group {
            normalResults
                .previewDisplayName("Normal Results")
            
            emptyResults
                .previewDisplayName("Empty Results")
            
            fewResults
                .previewDisplayName("Few Results")
            
            mixedStates
                .previewDisplayName("Mixed States")
            
            normalResults
                .preferredColorScheme(.dark)
                .previewDisplayName("Dark Mode")
            
            fewResults
                .environment(\.sizeCategory, .accessibilityExtraExtraExtraLarge)
                .previewDisplayName("Large Text")
        }
    }
}
