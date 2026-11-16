import SwiftUI
import UIKit

struct AuthenticatedRootView: View {
  /// Tells `AppRootView` whether the onboarding state is still loading, so its one launch logo
  /// stays over this view until there is a real screen to show.
  @Binding var isLoading: Bool

  @EnvironmentObject private var authModel: AuthModel
  @StateObject private var onboardingViewModel = OnboardingViewModel()

  var body: some View {
    // No animation on these swaps. A guest who links an account changes `rootTaskID`, which
    // reloads and rebuilds `MainTabView`; a crossfade there could show two tab views at once.
    Group {
      if onboardingViewModel.isLoading {
        // `AppRootView`'s logo covers this.
        Color.theme.background
          .ignoresSafeArea()
      } else if onboardingViewModel.shouldShowOnboarding {
        OnboardingFlowView(viewModel: onboardingViewModel)
      } else {
        MainTabView()
      }
    }
    .onChange(of: onboardingViewModel.isLoading, initial: true) { _, newValue in
      isLoading = newValue
    }
    .task(id: rootTaskID) {
      await onboardingViewModel.loadState(
        for: authModel.currentUserId,
        isAnonymous: authModel.isAnonymous
      )
    }
  }

  private var rootTaskID: String {
    "\(authModel.currentUserId ?? "none")-\(authModel.isAnonymous)"
  }
}
