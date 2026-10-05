//
//  AIQueryCard.swift
//  TTB
//
//  Created by AI Assistant on 2025-07-18.
//

import SwiftUI

struct AIQueryCard: View {
    let query: AIQuery
    @EnvironmentObject private var aiModel: AIModel
    @State private var isExpanded = false
    @State private var showingShareSheet = false
    @State private var showingConvertDialog = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            headerView
            
            // Question
            questionView
            
            // Responses
            responsesView
            
            // Actions
            if query.isComplete {
                actionsView
            }
        }
        .padding()
        .background(Color.theme.background)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(query.error != nil ? Color.red.opacity(0.3) : Color.clear, lineWidth: 1)
        )
        .sheet(isPresented: $showingShareSheet) {
            AIShareSheet(query: query)
        }
        .confirmationDialog(String(localized: "ai.queryCard.convertTitle"), isPresented: $showingConvertDialog) {
            Button(String(localized: "ai.queryCard.convertConfirmAction")) {
                Task {
                    await aiModel.convertToQuestion(query)
                }
            }
            Button(String(localized: "common.cancel"), role: .cancel) {}
        } message: {
            Text(String(localized: "ai.queryCard.convertConfirm"))
        }
        .animation(.easeInOut(duration: 0.2), value: isExpanded)
    }
    
    // MARK: - Header View
    private var headerView: some View {
        HStack {
            // Category Icon and Name
            HStack(spacing: 6) {
                Image(systemName: query.category.icon)
                    .foregroundColor(.accentColor)
                    .font(.caption)
                
                Text(query.category.localizedName)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.accentColor.opacity(0.1))
            .cornerRadius(8)
            
            Spacer()
            
            // Timestamp
            Text(query.formattedTimestamp)
                .font(.caption)
                .foregroundColor(.secondary)
            
            // Status Indicator
            if query.isLoading {
                ProgressView()
                    .scaleEffect(0.8)
                    .progressViewStyle(CircularProgressViewStyle(tint: .accentColor))
            } else if query.error != nil {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.red)
                    .font(.caption)
            } else if query.isComplete {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.caption)
            }
        }
    }
    
    // MARK: - Question View
    private var questionView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(String(localized: "ai.queryCard.questionLabel"))
                    .font(.caption.bold())
                    .foregroundColor(.secondary)
                
                Spacer()
                
                if query.question.count > 100 {
                    Button(action: { isExpanded.toggle() }) {
                        Text(isExpanded ? String(localized: "common.collapse") : String(localized: "common.expand"))
                            .font(.caption)
                            .foregroundColor(.accentColor)
                    }
                }
            }
            
            Text(query.question)
                .font(.body.weight(.medium))
                .foregroundColor(.primary)
                .lineLimit(isExpanded ? nil : 3)
        }
    }
    
    // MARK: - Responses View
    private var responsesView: some View {
        Group {
            if query.isLoading {
                loadingResponsesView
            } else if let error = query.error {
                errorResponseView(error: error)
            } else if query.isComplete {
                completedResponsesView
            }
        }
    }
    
    private var loadingResponsesView: some View {
        VStack(spacing: 12) {
            HStack {
                ProgressView()
                    .scaleEffect(0.8)
                
                Text(String(localized: "ai.queryCard.loading"))
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
            }
            
            // Placeholder responses
            ForEach(0..<3, id: \.self) { index in
                HStack(alignment: .top, spacing: 8) {
                    Text("\(index + 1)")
                        .font(.caption.weight(.bold))
                        .foregroundColor(.accentColor)
                        .frame(width: 20, alignment: .leading)
                    
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.3))
                        .frame(height: 20)
                        .redacted(reason: .placeholder)
                }
            }
        }
        .padding(.top, 8)
    }
    
    private func errorResponseView(error: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.red)
                .font(.caption)
            
            Text(error)
                .font(.caption)
                .foregroundColor(.red)
                .lineLimit(2)
            
            Spacer()
            
            Button(String(localized: "ai.queryCard.retry")) {
                Task {
                    await aiModel.askQuestion(query.question, category: query.category)
                }
            }
            .font(.caption)
            .foregroundColor(.accentColor)
        }
        .padding(.top, 8)
    }
    
    private var completedResponsesView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(String(localized: "ai.queryCard.responsesLabel"))
                    .font(.caption.bold())
                    .foregroundColor(.secondary)
                
                Spacer()
                
                if query.responses.joined().count > 200 {
                    Button(action: { isExpanded.toggle() }) {
                        Text(isExpanded ? String(localized: "common.collapse") : String(localized: "common.expand"))
                            .font(.caption)
                            .foregroundColor(.accentColor)
                    }
                }
            }
            
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(query.responses.enumerated()), id: \.offset) { index, response in
                    responseItemView(number: index + 1, response: response)
                }
            }
        }
        .padding(.top, 8)
    }
    
    private func responseItemView(number: Int, response: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            // Number Badge
            ZStack {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 24, height: 24)
                
                Text("\(number)")
                    .font(.caption.bold())
                    .foregroundColor(.white)
            }
            
            // Response Text
            Text(response)
                .font(.body)
                .foregroundColor(.primary)
                .lineLimit(isExpanded ? nil : 3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
    
    // MARK: - Actions View
    private var actionsView: some View {
        HStack(spacing: 16) {
            Button(action: { showingShareSheet = true }) {
                HStack(spacing: 4) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.caption)
                    
                    Text(String(localized: "common.share"))
                        .font(.caption)
                }
                .foregroundColor(.accentColor)
            }
            
            Button(action: {
                Task {
                    await aiModel.saveQuery(query)
                }
            }) {
                HStack(spacing: 4) {
                    Image(systemName: query.isSaved ? "bookmark.fill" : "bookmark")
                        .font(.caption)
                    
                    Text(query.isSaved ? String(localized: "ai.history.saved") : String(localized: "common.save"))
                        .font(.caption)
                }
                .foregroundColor(query.isSaved ? .green : .accentColor)
            }
            .disabled(query.isSaved)
            
            Button(action: { showingConvertDialog = true }) {
                HStack(spacing: 4) {
                    Image(systemName: "questionmark.circle")
                        .font(.caption)
                    
                    Text(String(localized: "ai.queryCard.convertTitle"))
                        .font(.caption)
                }
                .foregroundColor(.accentColor)
            }
            
            Spacer()
            
            Button(action: {
                Task {
                    await aiModel.deleteQuery(query)
                }
            }) {
                Image(systemName: "trash")
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
        .padding(.top, 8)
    }
}

// MARK: - Preview
struct AIQueryCard_Previews: PreviewProvider {
    // MARK: - Individual Preview Components
    static var completeQuery: some View {
        ScrollView {
            VStack(spacing: 16) {
                AIQueryCard(query: AIQuery.sampleQueries[0])
                    .environmentObject(AIModel.sample)
            }
            .padding()
        }
        .background(Color.theme.secondaryBackground)
    }
    
    static var loadingQuery: some View {
        ScrollView {
            VStack(spacing: 16) {
                AIQueryCard(query: AIQuery(
                    question: "Bu sorunun cevabı bekleniyor...",
                    responses: [],
                    timestamp: Date(),
                    category: .personal,
                    isSaved: false,
                    isLoading: true,
                    error: nil
                ))
                .environmentObject(AIModel.sample)
            }
            .padding()
        }
        .background(Color.theme.secondaryBackground)
    }
    
    static var errorQuery: some View {
        ScrollView {
            VStack(spacing: 16) {
                AIQueryCard(query: AIQuery(
                    question: "Bu soru hata verdi",
                    responses: [],
                    timestamp: Date(),
                    category: .career,
                    isSaved: false,
                    isLoading: false,
                    error: "Ağ bağlantısı hatası. Lütfen internet bağlantınızı kontrol edin."
                ))
                .environmentObject(AIModel.sample)
            }
            .padding()
        }
        .background(Color.theme.secondaryBackground)
    }
    
    static var savedQuery: some View {
        ScrollView {
            VStack(spacing: 16) {
                AIQueryCard(query: AIQuery(
                    question: "Bu soru kaydedilmiş durumda",
                    responses: [
                        "Kaydedilmiş sorular bookmark ikonu ile gösterilir",
                        "Kaydedilmiş sorular kullanıcı tarafından kolayca erişilebilir",
                        "Bu özellik favori sorular için kullanılır"
                    ],
                    timestamp: Date(),
                    category: .health,
                    isSaved: true,
                    isLoading: false,
                    error: nil
                ))
                .environmentObject(AIModel.sample)
            }
            .padding()
        }
        .background(Color.theme.secondaryBackground)
    }
    
    static var previews: some View {
        Group {
            completeQuery
                .previewDisplayName("Complete Query")
            
            loadingQuery
                .previewDisplayName("Loading State")
            
            errorQuery
                .previewDisplayName("Error State")
            
            savedQuery
                .previewDisplayName("Saved Query")
            
            completeQuery
                .preferredColorScheme(.dark)
                .previewDisplayName("Dark Mode")
            
            completeQuery
                .environment(\.sizeCategory, .accessibilityExtraExtraExtraLarge)
                .previewDisplayName("Large Text")
        }
    }
}
