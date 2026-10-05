//
//  AILoadingView.swift
//  TTB
//
//  Created by AI Assistant on 2025-07-18.
//

import SwiftUI

struct AILoadingView: View {
    let message: String
    @State private var animationRotation: Double = 0
    @State private var pulseScale: CGFloat = 1.0
    
    var body: some View {
        VStack(spacing: 20) {
            // Animated Loading Icon
            ZStack {
                Circle()
                    .stroke(Color.accentColor.opacity(0.3), lineWidth: 4)
                    .frame(width: 60, height: 60)
                
                Circle()
                    .trim(from: 0.0, to: 0.7)
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .frame(width: 60, height: 60)
                    .rotationEffect(.degrees(animationRotation))
                    .animation(.linear(duration: 1.0).repeatForever(autoreverses: false), value: animationRotation)
                
                Image(systemName: "brain.head.profile")
                    .font(.title2)
                    .foregroundColor(.accentColor)
                    .scaleEffect(pulseScale)
                    .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: pulseScale)
            }
            
            // Loading Message
            Text(message)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(3)
            
            // Thinking Animation
            HStack(spacing: 4) {
                ForEach(0..<3) { index in
                    Circle()
                        .fill(Color.accentColor.opacity(0.6))
                        .frame(width: 8, height: 8)
                        .scaleEffect(pulseScale)
                        .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true).delay(Double(index) * 0.2), value: pulseScale)
                }
            }
            .padding(.top, 8)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color.theme.secondaryBackground)
        .cornerRadius(16)
        .onAppear {
            animationRotation = 360
            pulseScale = 1.2
        }
    }
}

struct AIThinkingView: View {
    @State private var animationPhase: Int = 0
    
    var body: some View {
        VStack(spacing: 16) {
            // Brain Animation
            Image(systemName: "brain.head.profile")
                .font(.system(size: 50))
                .foregroundColor(.accentColor)
                .opacity(0.3 + Double(animationPhase) * 0.2)
                .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: animationPhase)
            
            Text(String(localized: "ai.queryCard.loading"))
                .font(.headline)
                .foregroundColor(.primary)
            
            Text(String(localized: "ai.loading.subtitle"))
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            // Animated Dots
            HStack(spacing: 6) {
                ForEach(0..<5) { index in
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 6, height: 6)
                        .opacity(animationPhase == index ? 1.0 : 0.3)
                        .animation(.easeInOut(duration: 0.3).delay(Double(index) * 0.1), value: animationPhase)
                }
            }
            .padding(.top, 8)
        }
        .padding()
        .task {
            // SwiftUI cancels this task when the view goes away; the sleep then throws and
            // the loop ends.
            do {
                while true {
                    try await Task.sleep(for: .milliseconds(500))
                    animationPhase = (animationPhase + 1) % 5
                }
            } catch {}
        }
    }
}


struct AIEmptyView: View {
    let title: String
    let message: String
    let systemImage: String
    let actionTitle: String?
    let action: (() -> Void)?
    
    init(title: String, message: String, systemImage: String = "tray", actionTitle: String? = nil, action: (() -> Void)? = nil) {
        self.title = title
        self.message = message
        self.systemImage = systemImage
        self.actionTitle = actionTitle
        self.action = action
    }
    
    var body: some View {
        VStack(spacing: 20) {
            // Empty Icon
            Image(systemName: systemImage)
                .font(.system(size: 50))
                .foregroundColor(.secondary)
            
            // Empty Title
            Text(title)
                .font(.headline)
                .foregroundColor(.primary)
            
            // Empty Message
            Text(message)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(5)
            
            // Action Button
            if let actionTitle = actionTitle, let action = action {
                Button(action: action) {
                    Text(actionTitle)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
                .padding(.top, 8)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Preview
struct AILoadingView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            // Basic Loading View
            AILoadingView(message: String(localized: "ai.queryCard.loading"))
                .previewDisplayName("Basic Loading")
            
            // Long Message Loading
            AILoadingView(message: "AI asistanınız sorunuzu analiz ediyor ve size en iyi üç yanıtı hazırlıyor...")
                .previewDisplayName("Long Message Loading")
            
            // Short Message Loading
            AILoadingView(message: "Yükleniyor...")
                .previewDisplayName("Short Message Loading")
            
            // Different Messages
            AILoadingView(message: "Yanıtlar hazırlanıyor...")
                .previewDisplayName("Preparing Responses")
            
            AILoadingView(message: "İçerik işleniyor...")
                .previewDisplayName("Processing Content")
            
            // Thinking View
            AIThinkingView()
                .previewDisplayName("Thinking View")
            
            // Loading in Dark Mode
            AILoadingView(message: String(localized: "ai.queryCard.loading"))
                .preferredColorScheme(.dark)
                .previewDisplayName("Dark Mode Loading")
            
            // Empty State Views
            AIEmptyView(
                title: "Henüz sorgu yok",
                message: "AI asistanına ilk sorunuzu sorun",
                systemImage: "questionmark.circle",
                actionTitle: "Soru Sor",
                action: {}
            )
            .previewDisplayName("Empty - No Queries")
            
            AIEmptyView(
                title: "Sonuç bulunamadı",
                message: "Arama kriterlerinize uygun sonuç bulunamadı. Lütfen farklı anahtar kelimeler deneyin.",
                systemImage: "magnifyingglass",
                actionTitle: "Yeni Arama",
                action: {}
            )
            .previewDisplayName("Empty - No Results")
            
            AIEmptyView(
                title: "Bağlantı Sorunu",
                message: "İnternet bağlantınızı kontrol edin",
                systemImage: "wifi.slash",
                actionTitle: "Yeniden Dene",
                action: {}
            )
            .previewDisplayName("Empty - Connection Issue")
            
            // Empty without action
            AIEmptyView(
                title: "Bakım Modu",
                message: "Sistem şu anda bakım modunda. Lütfen daha sonra tekrar deneyin.",
                systemImage: "wrench.and.screwdriver"
            )
            .previewDisplayName("Empty - Maintenance")
            
            // Loading in different sizes
            VStack {
                AILoadingView(message: "Küçük alan")
                    .frame(height: 100)
                    .border(Color.gray, width: 1)
                
                AILoadingView(message: "Orta alan")
                    .frame(height: 200)
                    .border(Color.gray, width: 1)
                
                AILoadingView(message: "Büyük alan")
                    .frame(height: 300)
                    .border(Color.gray, width: 1)
            }
            .previewDisplayName("Different Sizes")
            
            // Loading with Large Text
            AILoadingView(message: "Büyük metin boyutu ile yükleniyor...")
                .environment(\.sizeCategory, .accessibilityExtraExtraExtraLarge)
                .previewDisplayName("Large Text Loading")
        }
        .padding()
    }
}
