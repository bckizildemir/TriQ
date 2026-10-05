//
//  AIPreviewCollection.swift
//  TTB
//
//  Created by Kilo Code on 2025-07-18.
//

import SwiftUI

/// Simple preview collection for AI views
struct AIPreviewCollection: View {
    var body: some View {
        NavigationView {
            List {
                Section(header: Text(String(localized: "ai.preview.collection.views"))) {
                    NavigationLink(String(localized: "ai.preview.collection.mainView"), destination: AIView())
                    NavigationLink(String(localized: "ai.preview.collection.inputView"), destination: AIQueryInputView())
                    NavigationLink(String(localized: "ai.preview.collection.resultsView"), destination: AIResultsView(queries: [sampleQuery]))
                    NavigationLink(String(localized: "ai.preview.collection.historyView"), destination: AIHistoryView())
                }
                
                Section(header: Text(String(localized: "ai.preview.collection.components"))) {
                    NavigationLink(String(localized: "ai.preview.collection.queryCard"), destination: AIQueryCard(query: sampleQuery))
                    NavigationLink(String(localized: "ai.preview.collection.loadingView"), destination: AILoadingView(message: String(localized: "ai.preview.loadingThinking")))
                    NavigationLink(String(localized: "ai.preview.collection.errorView"), destination: AIErrorView(error: String(localized: "ai.preview.collection.sampleError"), retryAction: {}))
                }
            }
            .navigationTitle(String(localized: "ai.preview.collection.title"))
        }
        .environmentObject(mockAIModel)
    }
    
    // Simple mock data
    private var sampleQuery: AIQuery {
        AIQuery(
            question: String(localized: "ai.preview.collection.sampleQuestion"),
            responses: [
                String(localized: "ai.preview.collection.sampleResponse1"),
                String(localized: "ai.preview.collection.sampleResponse2"),
                String(localized: "ai.preview.collection.sampleResponse3")
            ],
            category: .recommendations
        )
    }
    
    private var mockAIModel: AIModel {
        AIModel()
    }
}

// MARK: - SwiftUI Previews

struct AIPreviewCollection_Previews: PreviewProvider {
    static var previews: some View {
        AIPreviewCollection()
    }
}
