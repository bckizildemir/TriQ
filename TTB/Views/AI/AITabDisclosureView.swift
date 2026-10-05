import SwiftUI

struct AITabDisclosureView: View {
    let onContinue: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hasAppeared = false

    var body: some View {
        ZStack {
            backgroundLayer

            ScrollView(showsIndicators: false) {
                VStack(spacing: 30) {
                    Spacer(minLength: 12)
                    hero
                    introSection
                    noteSection
                }
                .padding(.horizontal, 24)
                .padding(.top, 28)
                .padding(.bottom, 140)
                .frame(maxWidth: .infinity)
            }
        }
        .safeAreaInset(edge: .bottom) {
            footer
        }
        .interactiveDismissDisabled()
        .onAppear {
            guard !hasAppeared else { return }

            if reduceMotion {
                hasAppeared = true
            } else {
                withAnimation(.spring(response: 0.56, dampingFraction: 0.86)) {
                    hasAppeared = true
                }
            }
        }
    }

    private var backgroundLayer: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color.black,
                    Color(red: 0.08, green: 0.09, blue: 0.12),
                    Color(red: 0.04, green: 0.05, blue: 0.08),
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            Circle()
                .fill(Color.accentColor.opacity(0.16))
                .frame(width: 260, height: 260)
                .blur(radius: 40)
                .offset(x: -130, y: -280)

            Circle()
                .fill(Color.orange.opacity(0.14))
                .frame(width: 240, height: 240)
                .blur(radius: 44)
                .offset(x: 150, y: -210)
        }
        .ignoresSafeArea()
    }

    private var hero: some View {
        ZStack {
            bubble(
                color: Color(red: 0.58, green: 0.46, blue: 0.97),
                symbol: "quote.bubble.fill",
                size: 132,
                yOffset: -8
            )
            .offset(x: -108)

            bubble(
                color: Color(red: 0.99, green: 0.83, blue: 0.28),
                symbol: "sparkles",
                size: 168,
                yOffset: 0
            )

            bubble(
                color: Color(red: 1.0, green: 0.43, blue: 0.43),
                symbol: "person.2.fill",
                size: 132,
                yOffset: -8
            )
            .offset(x: 108)
        }
        .frame(height: 220)
        .scaleEffect(hasAppeared ? 1 : 0.92)
        .opacity(hasAppeared ? 1 : 0.0)
        .accessibilityHidden(true)
    }

    private func bubble(color: Color, symbol: String, size: CGFloat, yOffset: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [color.opacity(0.96), color.opacity(0.74)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.16), lineWidth: 1)
                )
                .shadow(color: color.opacity(0.3), radius: 28, y: 16)

            Image(systemName: symbol)
                .font(.system(size: size * 0.3, weight: .semibold))
                .foregroundStyle(Color.black.opacity(0.72))
                .offset(y: yOffset)
        }
        .frame(width: size, height: size)
    }

    private var introSection: some View {
        VStack(spacing: 14) {
            Text(String(localized: "ai.trioDisclosure.title"))
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)

            Text(String(localized: "ai.trioDisclosure.body"))
                .font(.title3)
                .foregroundStyle(Color.white.opacity(0.82))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: 520)
        .opacity(hasAppeared ? 1 : 0.0)
        .offset(y: hasAppeared ? 0 : 10)
    }

    private var noteSection: some View {
        VStack(spacing: 14) {
            noteCard(
                text: String(localized: "ai.trioDisclosure.aiNote"),
                systemImage: "exclamationmark.bubble.fill",
                tint: .yellow
            )

            noteCard(
                text: String(localized: "ai.trioDisclosure.privacyNote"),
                systemImage: "hand.raised.fill",
                tint: .green
            )
        }
        .frame(maxWidth: 560)
        .opacity(hasAppeared ? 1 : 0.0)
        .offset(y: hasAppeared ? 0 : 12)
    }

    private func noteCard(text: String, systemImage: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: systemImage)
                .font(.headline)
                .foregroundStyle(tint)
                .frame(width: 24)
                .padding(.top, 2)
                .accessibilityHidden(true)

            Text(text)
                .font(.subheadline)
                .foregroundStyle(Color.white.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 22)
                .fill(Color.white.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 22)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
        )
    }

    private var footer: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 1)

            Button(action: onContinue) {
                Text(String(localized: "ai.trioDisclosure.cta"))
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 56)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.accentColor)
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 24)
        }
        .background(Color.black.opacity(0.86))
    }
}

#Preview {
    AITabDisclosureView(onContinue: {})
}
