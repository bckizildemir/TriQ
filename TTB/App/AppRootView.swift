import SwiftUI

struct AppRootView: View {
  @EnvironmentObject private var authModel: AuthModel

  var body: some View {
    Group {
      switch authModel.authState {
      case .checking:
        LaunchLoadingView()
          .transition(.opacity)
      case .authenticated:
        AuthenticatedRootView()
          .transition(.opacity)
      case .signedOut:
        LoginView()
          .transition(.opacity)
      }
    }
    // Opacity only, so it stays on under Reduce Motion.
    .animation(.easeOut(duration: 0.25), value: authModel.authState)
  }
}

/// The app logo, shown from cold start until the app is ready. `AuthenticatedRootView` shows the
/// same view while the onboarding state loads, so the logo stays up through both waits.
struct LaunchLoadingView: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var isAnimating = false

  var body: some View {
    ZStack {
      Color.theme.background
        .ignoresSafeArea()

      Image("LaunchLogo")
        .resizable()
        .scaledToFit()
        .frame(width: 128, height: 128)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .scaleEffect(reduceMotion ? 1 : (isAnimating ? 1.035 : 0.985))
        .opacity(reduceMotion ? 1 : (isAnimating ? 1 : 0.88))
        .animation(
          reduceMotion ? nil : .easeInOut(duration: 0.9).repeatForever(autoreverses: true),
          value: isAnimating
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "common.loading"))
        .accessibilityIdentifier("launch-loading-logo")
    }
    .onAppear {
      isAnimating = !reduceMotion
    }
    .onChange(of: reduceMotion) { _, newValue in
      isAnimating = !newValue
    }
  }
}
