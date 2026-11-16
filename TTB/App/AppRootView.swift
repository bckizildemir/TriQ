import SwiftUI

struct AppRootView: View {
  @EnvironmentObject private var authModel: AuthModel

  /// True while the signed-in root still loads its onboarding state.
  @State private var isAuthenticatedRootLoading = true
  /// The one launch logo, laid over the root. It covers the auth check and the onboarding-state
  /// load as a single view, so it neither restarts its pulse nor lets the window show through.
  @State private var isShowingLaunchCover = true

  /// Whether the app is still waiting for something before it can show a real screen.
  private var isWaiting: Bool {
    switch authModel.authState {
    case .checking:
      true
    case .authenticated:
      isAuthenticatedRootLoading
    case .signedOut:
      false
    }
  }

  var body: some View {
    ZStack {
      // The screen under the logo swaps without animation, so a swap never puts two copies of
      // a root (two tab views) on screen at once. Only the logo fades.
      Group {
        switch authModel.authState {
        case .checking:
          Color.theme.background
            .ignoresSafeArea()
        case .authenticated:
          AuthenticatedRootView(isLoading: $isAuthenticatedRootLoading)
        case .signedOut:
          LoginView()
        }
      }

      if isShowingLaunchCover {
        LaunchLoadingView()
          .transition(.opacity)
          .zIndex(1)
      }
    }
    .onChange(of: authModel.authState) { _, newState in
      // A later sign-in starts from "loading" again, not from the last session's value.
      if newState != .authenticated {
        isAuthenticatedRootLoading = true
      }
    }
    .task(id: isWaiting) {
      await updateLaunchCover(isWaiting: isWaiting)
    }
  }

  /// Shows the logo while the app waits, and fades it out once the screen under it has drawn.
  ///
  /// Hiding the logo in the same update that builds the next screen loses the fade: building
  /// `MainTabView` holds the main thread past the 0.25 s, so the first frame drawn is already the
  /// end state. The short wait lets that update commit and draw under the logo first. It is not a
  /// minimum display time: a fast launch still ends as soon as the app is ready.
  private func updateLaunchCover(isWaiting: Bool) async {
    // Opacity only, so it stays on under Reduce Motion.
    let fade = Animation.easeOut(duration: 0.25)

    guard !isWaiting else {
      if !isShowingLaunchCover {
        withAnimation(fade) { isShowingLaunchCover = true }
      }
      return
    }
    guard isShowingLaunchCover else { return }

    do {
      try await Task.sleep(for: .milliseconds(100))
    } catch {
      return
    }
    withAnimation(fade) { isShowingLaunchCover = false }
  }
}

/// The app logo, shown from cold start until the app is ready. `AppRootView` lays one instance
/// over the root for every wait: the auth check and the onboarding-state load.
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
