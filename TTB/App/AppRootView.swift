import SwiftUI

struct AppRootView: View {
  @EnvironmentObject private var authModel: AuthModel

  var body: some View {
    Group {
      switch authModel.authState {
      case .checking:
        LaunchLoadingView()
      case .authenticated:
        AuthenticatedRootView()
      case .signedOut:
        LoginView()
      }
    }
  }
}

private struct LaunchLoadingView: View {
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
    }
    .onAppear {
      isAnimating = !reduceMotion
    }
    .onChange(of: reduceMotion) { _, newValue in
      isAnimating = !newValue
    }
  }
}
