import SwiftUI

struct BadgeUnlockView: View {
    let badge: Badge
    let onDismiss: () -> Void
    
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Starts at the full-motion scale; `onAppear` sets it from `BadgeUnlockMotion`.
    @State private var badgeScale: CGFloat = 0.85
    @State private var badgeOpacity: Double = 0
    @State private var opacity: Double = 0

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
                .scaleEffect(badgeScale)
                .opacity(badgeOpacity)
                
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
            HapticLog.record("badge-unlock-success")

            // Set without animation: under Reduce Motion the badge starts at full size and only fades.
            let motion = BadgeUnlockMotion(reduceMotion: reduceMotion)
            badgeScale = motion.initialBadgeScale

            withAnimation(motion.badgeAnimation) {
                badgeScale = 1.0
                badgeOpacity = 1.0
            }

            withAnimation(motion.textAnimation) {
                opacity = 1.0
            }
        }
        .accessibilityIdentifier("badge-unlock")
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
    
    /// Closes in one move: the sheet's own slide-down is the exit.
    private func dismiss() {
        onDismiss()
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
