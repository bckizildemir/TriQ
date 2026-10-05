import SwiftUI
import UIKit

struct AuthenticatedRootView: View {
  @EnvironmentObject private var authModel: AuthModel
  @StateObject private var onboardingViewModel = OnboardingViewModel()

  var body: some View {
    Group {
      if onboardingViewModel.isLoading {
        ZStack {
          Color.theme.background
            .ignoresSafeArea()

          ProgressView(String(localized: "common.loading"))
        }
      } else if onboardingViewModel.shouldShowOnboarding {
        OnboardingFlowView(viewModel: onboardingViewModel)
      } else {
        MainTabView()
      }
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
