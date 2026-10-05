//
//  AIShareSheet.swift
//  TTB
//
//  Created by AI Assistant on 2025-07-18.
//

import SwiftUI

struct AIShareSheet: View {
    let query: AIQuery
    @Environment(\.toastCenter) private var toastCenter
    @Environment(\.dismiss) private var dismiss
    @State private var shareText = ""
    @State private var includeResponses = true
    @State private var showingActivityView = false
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Share Options
                    VStack(alignment: .leading, spacing: 16) {
                        Text(String(localized: "ai.share.optionsTitle"))
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        Toggle(String(localized: "ai.share.includeResponses"), isOn: $includeResponses)
                            .toggleStyle(SwitchToggleStyle())
                    }
                    .padding()
                    .background(Color.theme.secondaryBackground)
                    .cornerRadius(12)
                    
                    // Preview
                    VStack(alignment: .leading, spacing: 16) {
                        Text(String(localized: "ai.share.previewTitle"))
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        Text(generateShareText())
                            .font(.body)
                            .foregroundColor(.secondary)
                            .padding()
                            .background(Color.theme.background)
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                            )
                    }
                    .padding()
                    .background(Color.theme.secondaryBackground)
                    .cornerRadius(12)
                    
                    // Share Actions
                    VStack(spacing: 12) {
                        Button(action: shareToActivityView) {
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
                        
                        Button(action: copyToClipboard) {
                            HStack {
                                Image(systemName: "doc.on.doc")
                                Text(String(localized: "common.copy"))
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.theme.secondaryBackground)
                            .foregroundColor(.primary)
                            .cornerRadius(12)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle(String(localized: "common.share"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(String(localized: "common.close")) {
                        dismiss()
                    }
                }
            }
        }
        .sheet(isPresented: $showingActivityView) {
            ActivityViewController(activityItems: [generateShareText()])
        }
    }
    
    private func generateShareText() -> String {
        var text = "🤖 \(String(localized: "ai.share.text.assistantTitle"))\n\n"
        text += "📝 \(String(localized: "ai.share.text.questionLabel")): \(query.question)\n"
        text += "🏷️ \(String(localized: "ai.share.text.categoryLabel")): \(query.category.localizedName)\n\n"
        
        if includeResponses && query.isComplete {
            text += "💡 \(String(localized: "ai.share.text.responsesLabel")):\n"
            for (index, response) in query.responses.enumerated() {
                text += "\(index + 1). \(response)\n\n"
            }
        }
        
        text += "📱 \(String(localized: "ai.share.text.footer"))"
        
        return text
    }
    
    private func shareToActivityView() {
        showingActivityView = true
    }
    
    private func copyToClipboard() {
        UIPasteboard.general.string = generateShareText()
        
        // Show success feedback
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()
        toastCenter.showSuccess(
            title: String(localized: "toast.copied"),
            accessibilityIdentifier: "ai-share-copy-toast"
        )
        
        dismiss()
    }
}

// MARK: - Activity View Controller
struct ActivityViewController: UIViewControllerRepresentable {
    let activityItems: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Preview
struct AIShareSheet_Previews: PreviewProvider {
    // MARK: - Individual Preview Components
    static var completeQuery: some View {
        AIShareSheet(query: AIQuery.sampleQueries[0])
    }
    
    static var queryWithoutResponses: some View {
        AIShareSheet(query: AIQuery(
            question: "Bu soru henüz yanıtlanmamış",
            responses: [],
            timestamp: Date(),
            category: .advice,
            isSaved: false,
            isLoading: false,
            error: nil
        ))
    }
    
    static var longContent: some View {
        AIShareSheet(query: AIQuery(
            question: "Bu çok uzun bir soru metni örneğidir. Kullanıcılar bazen çok detaylı ve karmaşık sorular sorabilirler ve bu durumda paylaşım ekranının bu tür uzun metinleri düzgün bir şekilde görüntüleyebilmesi çok önemlidir.",
            responses: [
                "Bu çok uzun bir yanıt metni örneğidir. AI asistanı bazen çok detaylı ve kapsamlı yanıtlar verebilir.",
                "İkinci yanıt da benzer şekilde uzun ve detaylı olabilir.",
                "Üçüncü yanıt da kapsamlı bilgiler içerebilir."
            ],
            timestamp: Date(),
            category: .creativity,
            isSaved: false,
            isLoading: false,
            error: nil
        ))
    }
    
    static var shortContent: some View {
        AIShareSheet(query: AIQuery(
            question: "Kısa soru",
            responses: [
                "Kısa yanıt 1",
                "Kısa yanıt 2",
                "Kısa yanıt 3"
            ],
            timestamp: Date(),
            category: .productivity,
            isSaved: false,
            isLoading: false,
            error: nil
        ))
    }
    
    static var previews: some View {
        Group {
            completeQuery
                .previewDisplayName("Complete Query")
            
            queryWithoutResponses
                .previewDisplayName("Query Without Responses")
            
            longContent
                .previewDisplayName("Long Content")
            
            shortContent
                .previewDisplayName("Short Content")
            
            completeQuery
                .preferredColorScheme(.dark)
                .previewDisplayName("Dark Mode")
            
            completeQuery
                .environment(\.sizeCategory, .accessibilityExtraExtraExtraLarge)
                .previewDisplayName("Large Text")
        }
    }
}
