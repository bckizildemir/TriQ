import SwiftUI

struct BadgeUnlockView: View {
    let badge: Badge
    let onDismiss: () -> Void
    
    @State private var scale: CGFloat = 0.5
    @State private var opacity: Double = 0
    @State private var rotation: Double = -180
    
    var body: some View {
        ZStack {
            // Background
            Color.black.opacity(0.7)
                .ignoresSafeArea()
                .onTapGesture {
                    dismiss()
                }
            
            VStack(spacing: 24) {
                // Badge Icon with animation
                ZStack {
                    // Glow effect
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [Color.accentColor.opacity(0.3), Color.clear],
                                center: .center,
                                startRadius: 0,
                                endRadius: 80
                            )
                        )
                        .frame(width: 160, height: 160)
                    
                    // Badge
                    Image(systemName: badge.icon)
                        .font(.system(size: 64))
                        .foregroundColor(.accentColor)
                        .frame(width: 120, height: 120)
                        .background(
                            Circle()
                                .fill(Color(.systemBackground))
                        )
                        .overlay(
                            Circle()
                                .stroke(Color.accentColor, lineWidth: 3)
                        )
                }
                .scaleEffect(scale)
                .rotationEffect(.degrees(rotation))
                
                VStack(spacing: 12) {
                    Text(String(localized: "badge.unlock.title"))
                        .font(.title2.bold())
                        .foregroundColor(.white)
                    
                    Text(badge.title)
                        .font(.title.bold())
                        .foregroundColor(.accentColor)
                        .multilineTextAlignment(.center)
                    
                    Text(badge.description)
                        .font(.body)
                        .foregroundColor(.white.opacity(0.9))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                .opacity(opacity)
                
                Button(action: dismiss) {
                    Text(String(localized: "badge.unlock.cta"))
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Color.accentColor)
                        .cornerRadius(12)
                        .padding(.horizontal, 32)
                }
                .opacity(opacity)
                .padding(.top, 16)
            }
            .padding()
        }
        .onAppear {
            // Haptic feedback
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
            
            // Animate badge appearance
            withAnimation(.spring(response: 0.6, dampingFraction: 0.6)) {
                scale = 1.0
                rotation = 0
            }
            
            withAnimation(.easeIn(duration: 0.3).delay(0.2)) {
                opacity = 1.0
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            String(
                format: String(localized: "badge.unlock.accessibility"),
                locale: AppLocalization.currentLocale,
                badge.title
            )
        )
        .accessibilityHint(badge.description)
    }
    
    private func dismiss() {
        withAnimation(.easeOut(duration: 0.2)) {
            scale = 0.8
            opacity = 0
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            onDismiss()
        }
    }
}

#Preview {
    BadgeUnlockView(
        badge: Badge(
            id: "first_answer",
            title: "İlk Adım",
            description: "İlk sorunuzu cevapladınız! Yolculuğunuz başladı.",
            icon: "1.circle.fill",
            isLocked: false,
            requirement: "1 soru cevaplayın",
            progress: 1.0,
            targetCount: 1,
            type: .total
        ),
        onDismiss: {}
    )
}
