import SwiftUI

struct OnboardingProgressBar: View {
  let progress: Double

  var body: some View {
    GeometryReader { proxy in
      ZStack(alignment: .leading) {
        Capsule()
          .fill(Color.theme.border.opacity(0.2))
          .frame(height: 4)

        Capsule()
          .fill(Color.accentColor.opacity(0.55))
          .frame(width: max(proxy.size.width * progress, 4), height: 4)
      }
    }
    .frame(height: 4)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(String(localized: "onboarding.progress.label"))
    .accessibilityValue(
      AppLocalization.prefersEnglish
        ? "\(Int(progress * 100)) percent"
        : "\(Int(progress * 100)) yüzde"
    )
  }
}
