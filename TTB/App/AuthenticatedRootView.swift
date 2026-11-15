import SwiftUI
import UIKit

struct AuthenticatedRootView: View {
  @EnvironmentObject private var authModel: AuthModel
  @StateObject private var onboardingViewModel = OnboardingViewModel()

  private enum RootPhase {
    case loading, onboarding, main
  }

  private var phase: RootPhase {
    if onboardingViewModel.isLoading { return .loading }
    return onboardingViewModel.shouldShowOnboarding ? .onboarding : .main
  }

  var body: some View {
    Group {
      switch phase {
      case .loading:
        // The same logo as the launch wait, so no second loader flashes in between.
        LaunchLoadingView()
          .transition(.opacity)
      case .onboarding:
        OnboardingFlowView(viewModel: onboardingViewModel)
          .transition(.opacity)
      case .main:
        MainTabView()
          .transition(.opacity)
      }
    }
    .animation(.easeOut(duration: 0.25), value: phase)
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
