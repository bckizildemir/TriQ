//
//  AIQueryDetailView.swift
//  TTB
//
//  Created by AI Assistant on 2025-07-18.
//

import SwiftUI

struct AIQueryDetailView: View {
    let query: AIQuery
    @EnvironmentObject private var aiModel: AIModel
    @Environment(\.toastCenter) private var toastCenter
    @Environment(\.dismiss) private var dismiss
    @State private var showingShareSheet = false
    @State private var showingDeleteConfirmation = false
    @State private var isRetrying = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header Section
                headerSection
                
                // Question Section
                questionSection
                
                // Responses Section
                responsesSection
                
                // Actions Section
                actionsSection
                
                // Metadata Section
                metadataSection
            }
            .padding()
        }
        .navigationTitle(String(localized: "ai.queryDetail.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    if query.isComplete {
                        Button(action: { showingShareSheet = true }) {
                            Label(String(localized: "common.share"), systemImage: "square.and.arrow.up")
                        }
                        
                        Button(action: {
                            Task {
                                await aiModel.saveQuery(query)
                            }
                        }) {
                            Label(query.isSaved ? String(localized: "ai.history.saved") : String(localized: "common.save"),
                                  systemImage: query.isSaved ? "bookmark.fill" : "bookmark")
                        }
                        .disabled(query.isSaved)
                    }
                    
                    if query.error != nil {
                        Button(action: retryQuery) {
                            Label(String(localized: "common.retry"), systemImage: "arrow.clockwise")
                        }
                    }
                    
                    Divider()
                    
                    Button(role: .destructive, action: { showingDeleteConfirmation = true }) {
                        Label(String(localized: "common.delete"), systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showingShareSheet) {
            AIShareSheet(query: query)
        }
        .alert(String(localized: "ai.queryDetail.deleteTitle"), isPresented: $showingDeleteConfirmation) {
            Button(String(localized: "common.cancel"), role: .cancel) { }
            Button(String(localized: "common.delete"), role: .destructive) {
                Task {
                    await aiModel.deleteQuery(query)
                    dismiss()
                }
            }
        } message: {
            Text(String(localized: "ai.queryDetail.deleteMessage"))
        }
    }
    
    // MARK: - Header Section
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Category and Status
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: query.category.icon)
                        .font(.body)
                        .foregroundColor(.accentColor)
                    
                    Text(query.category.localizedName)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Status Badge
                HStack(spacing: 4) {
                    if query.isLoading {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text(String(localized: "ai.queryDetail.statusLoading"))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else if query.error != nil {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundColor(.red)
                        Text(String(localized: "ai.queryDetail.statusError"))
                            .font(.caption)
                            .foregroundColor(.red)
                    } else if query.isComplete {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundColor(.green)
                        Text(String(localized: "ai.queryDetail.statusCompleted"))
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                }
            }
            
            // Timestamp
            Text(query.formattedTimestamp)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color.theme.secondaryBackground)
        .cornerRadius(12)
    }
    
    // MARK: - Question Section
    private var questionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(String(localized: "ai.queryDetail.questionLabel"))
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                
                Spacer()
                
                if query.isSaved {
                    Image(systemName: "bookmark.fill")
                        .font(.caption)
                        .foregroundColor(.accentColor)
                }
            }
            
            Text(query.question)
                .font(.body)
                .foregroundColor(.primary)
                .lineSpacing(4)
                .textSelection(.enabled)
        }
        .padding()
        .background(Color.theme.secondaryBackground)
        .cornerRadius(12)
    }
    
    // MARK: - Responses Section
    private var responsesSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(String(localized: "ai.queryDetail.responsesLabel"))
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                
                Spacer()
                
                if query.isComplete {
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
                AILoadingView(message: String(localized: "ai.queryCard.loading"))
                    .frame(height: 100)
            } else if let error = query.error {
                AIErrorView(error: error) {
                    retryQuery()
                }
                .frame(height: 200)
            } else if query.isComplete {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(Array(query.responses.enumerated()), id: \.offset) { index, response in
                        ResponseCard(number: index + 1, response: response)
                    }
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    
                    Text(String(localized: "ai.queryDetail.waiting"))
                        .font(.body)
                        .foregroundColor(.secondary)
                }
                .frame(height: 100)
            }
        }
        .padding()
        .background(Color.theme.secondaryBackground)
        .cornerRadius(12)
    }
    
    // MARK: - Actions Section
    private var actionsSection: some View {
        VStack(spacing: 12) {
            if query.isComplete {
                HStack(spacing: 12) {
                    Button(action: { showingShareSheet = true }) {
                        HStack {
                            Image(systemName: "square.and.arrow.up")
                            Text(String(localized: "common.share"))
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    
                    Button(action: {
                        Task {
                            await aiModel.saveQuery(query)
                        }
                    }) {
                        HStack {
                            Image(systemName: query.isSaved ? "bookmark.fill" : "bookmark")
                            Text(query.isSaved ? String(localized: "ai.history.saved") : String(localized: "common.save"))
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(query.isSaved ? Color.secondary.opacity(0.3) : Color.theme.secondaryBackground)
                        .foregroundColor(query.isSaved ? .secondary : .primary)
                        .cornerRadius(12)
                    }
                    .disabled(query.isSaved)
                }
            } else if query.error != nil {
                Button(action: retryQuery) {
                    HStack {
                        if isRetrying {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                        Text(String(localized: "common.retry"))
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                .disabled(isRetrying)
            }
            
            // Copy Question Button
            Button(action: copyQuestion) {
                HStack {
                    Image(systemName: "doc.on.doc")
                    Text(String(localized: "ai.queryDetail.copyQuestion"))
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.theme.secondaryBackground)
                .foregroundColor(.primary)
                .cornerRadius(12)
            }
            .accessibilityLabel(String(localized: "ai.queryDetail.copyQuestionA11yLabel"))
            .accessibilityHint(String(localized: "ai.queryDetail.copyQuestionA11yHint"))
            
            // Delete Button
            Button(action: {
                showingDeleteConfirmation = true
                let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                impactFeedback.impactOccurred()
            }) {
                HStack {
                    Image(systemName: "trash")
                    Text(String(localized: "common.delete"))
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.red.opacity(0.1))
                .foregroundColor(.red)
                .cornerRadius(12)
            }
            .accessibilityLabel(String(localized: "ai.queryDetail.deleteA11yLabel"))
            .accessibilityHint(String(localized: "ai.queryDetail.deleteA11yHint"))
        }
    }
    
    // MARK: - Metadata Section
    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "ai.queryDetail.infoTitle"))
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
            
            VStack(alignment: .leading, spacing: 8) {
                MetadataRow(title: String(localized: "ai.queryDetail.createdAt"), value: query.formattedTimestamp)
                MetadataRow(title: String(localized: "ai.queryDetail.category"), value: query.category.localizedName)
                MetadataRow(title: String(localized: "ai.queryDetail.status"), value: query.statusText)
                MetadataRow(title: String(localized: "ai.queryDetail.savedLabel"), value: query.isSaved ? String(localized: "common.yes") : String(localized: "common.no"))
                
                if query.isComplete {
                    MetadataRow(title: String(localized: "ai.queryDetail.characterCount"), value: "\(query.responses.joined().count)")
                    MetadataRow(title: String(localized: "ai.queryDetail.wordCount"), value: "\(query.responses.joined(separator: " ").split(separator: " ").count)")
                }
            }
        }
        .padding()
        .background(Color.theme.secondaryBackground)
        .cornerRadius(12)
    }
    
    // MARK: - Helper Methods
    private func retryQuery() {
        isRetrying = true
        Task {
            await aiModel.askQuestion(query.question, category: query.category)
            isRetrying = false
        }
    }
    
    private func copyQuestion() {
        UIPasteboard.general.string = query.question
        
        // Haptic feedback
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()
        toastCenter.showSuccess(
            title: String(localized: "toast.copied"),
            accessibilityIdentifier: "ai-query-copy-toast"
        )
    }
}

// MARK: - Response Card
struct ResponseCard: View {
    let number: Int
    let response: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Number Badge
            Text("\(number)")
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

// MARK: - Metadata Row
struct MetadataRow: View {
    let title: String
    let value: String
    
    var body: some View {
        HStack {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            
            Spacer()
            
            Text(value)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.primary)
        }
    }
}

// MARK: - Extensions
extension AIQuery {
    var statusText: String {
        if isLoading {
            return String(localized: "ai.queryDetail.statusLoading")
        } else if error != nil {
            return String(localized: "ai.queryDetail.statusError")
        } else if isComplete {
            return String(localized: "ai.queryDetail.statusCompleted")
        } else {
            return String(localized: "ai.queryDetail.statusPending")
        }
    }
}

// MARK: - Preview
struct AIQueryDetailView_Previews: PreviewProvider {
    // MARK: - Individual Preview Components
    static var completeQuery: some View {
        NavigationView {
            AIQueryDetailView(query: AIQuery.sampleQueries[0])
                .environmentObject(AIModel.sample)
        }
    }
    
    static var loadingQuery: some View {
        NavigationView {
            AIQueryDetailView(query: AIQuery(
                question: "Bu sorunun yanıtı şu anda hazırlanıyor. AI asistanı sorunuzu analiz ediyor ve size en uygun üç yanıtı sunacak.",
                responses: [],
                timestamp: Date(),
                category: .advice,
                isSaved: false,
                isLoading: true,
                error: nil
            ))
            .environmentObject(AIModel.sample)
        }
    }
    
    static var errorQuery: some View {
        NavigationView {
            AIQueryDetailView(query: AIQuery(
                question: "Bu soru hata verdi ve yanıtlanamadı. Lütfen tekrar deneyin.",
                responses: [],
                timestamp: Date(),
                category: .career,
                isSaved: false,
                isLoading: false,
                error: "Ağ bağlantısı hatası. Lütfen internet bağlantınızı kontrol edin ve tekrar deneyin."
            ))
            .environmentObject(AIModel.sample)
        }
    }
    
    static var savedQuery: some View {
        NavigationView {
            AIQueryDetailView(query: AIQuery(
                question: "Bu soru kaydedilmiş durumda ve favori listesinde yer alıyor.",
                responses: [
                    "Kaydedilmiş sorular kolayca erişilebilir hale gelir",
                    "Bookmark ikonu ile kaydedilmiş sorular işaretlenir",
                    "Favori sorular için hızlı erişim sağlanır"
                ],
                timestamp: Date(),
                category: .health,
                isSaved: true,
                isLoading: false,
                error: nil
            ))
            .environmentObject(AIModel.sample)
        }
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
