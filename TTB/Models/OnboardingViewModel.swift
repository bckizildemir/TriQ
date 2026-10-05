import Photos
import SwiftUI
import UIKit
import UserNotifications
import os

@MainActor
final class OnboardingViewModel: ObservableObject {
  @Published private(set) var shouldShowOnboarding = false
  @Published private(set) var isLoading = true
  @Published var currentStep: OnboardingStep = .welcome
  @Published var hasAcceptedLegal = false
  @Published private(set) var notificationStatus: OnboardingPermissionStatus = .notDetermined
  @Published private(set) var photoStatus: OnboardingPermissionStatus = .notDetermined
  @Published private(set) var isCompleting = false
  @Published var errorMessage: String?

  private let stateStore: OnboardingStateStore
  private let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.ttb.app",
    category: "Onboarding")
  private var currentUserId: String?
  private(set) var isAnonymousUser = false

  init(stateStore: OnboardingStateStore = OnboardingStateStore()) {
    self.stateStore = stateStore
  }

  var primaryButtonTitle: String {
    currentStep.isFinalStep
      ? String(localized: "onboarding.primaryButton.final")
      : String(localized: "onboarding.button.continue")
  }

  var canGoBack: Bool {
    currentStep.previous != nil
  }

  var canComplete: Bool {
    hasAcceptedLegal && !isCompleting
  }

  var termsURL: URL? {
    AppConfig.termsURL
  }

  var privacyURL: URL? {
    AppConfig.privacyURL
  }

  func loadState(for userId: String?, isAnonymous: Bool) async {
    currentUserId = userId
    isAnonymousUser = isAnonymous
    currentStep = .welcome
    hasAcceptedLegal = false
    errorMessage = nil
    isLoading = true
    await refreshPermissionStatuses()

    guard let userId else {
      shouldShowOnboarding = false
      isLoading = false
      return
    }

    do {
      shouldShowOnboarding = try await stateStore.hasCompletedCurrentOnboarding(for: userId) == false
    } catch {
      logger.error("Failed to load onboarding state: \(error.localizedDescription, privacy: .public)")
      shouldShowOnboarding = true
      errorMessage = String(localized: "onboarding.error.loadState")
    }

    isLoading = false
  }

  func goToNextStep() {
    guard let nextStep = currentStep.next else { return }
    withAnimation(.spring(response: 0.32, dampingFraction: 0.88)) {
      currentStep = nextStep
    }
  }

  func goBack() {
    guard let previousStep = currentStep.previous else { return }
    withAnimation(.spring(response: 0.32, dampingFraction: 0.88)) {
      currentStep = previousStep
    }
  }

  func skipToPermissions() {
    guard currentStep.canSkip else { return }
    withAnimation(.spring(response: 0.32, dampingFraction: 0.88)) {
      currentStep = .permissions
    }
  }

  func refreshPermissionStatuses() async {
    notificationStatus = await currentNotificationStatus()
    photoStatus = currentPhotoStatus()
  }

  func requestNotificationPermission() async {
    switch await currentNotificationStatus() {
    case .notDetermined:
      do {
        try await NotificationService.shared.requestAuthorization()
      } catch {
        errorMessage = String(localized: "onboarding.error.permissionRequest")
      }
    case .authorized, .limited:
      break
    case .denied:
      openAppSettings()
    }
    await refreshPermissionStatuses()
  }

  func requestPhotoPermission() async {
    let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)

    switch status {
    case .notDetermined:
      _ = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
    case .denied, .restricted:
      openAppSettings()
    case .authorized, .limited:
      break
    @unknown default:
      break
    }

    await refreshPermissionStatuses()
  }

  func completeOnboarding() async {
    guard canComplete, let currentUserId else { return }
    isCompleting = true
    defer { isCompleting = false }

    do {
      try await stateStore.completeCurrentOnboarding(for: currentUserId)
      shouldShowOnboarding = false
    } catch {
      logger.error("Failed to complete onboarding: \(error.localizedDescription, privacy: .public)")
      errorMessage = String(localized: "onboarding.complete.error")
    }
  }

  private func currentNotificationStatus() async -> OnboardingPermissionStatus {
    let settings = await UNUserNotificationCenter.current().notificationSettings()

    switch settings.authorizationStatus {
    case .authorized, .provisional, .ephemeral:
      return .authorized
    case .denied:
      return .denied
    case .notDetermined:
      return .notDetermined
    @unknown default:
      return .notDetermined
    }
  }

  private func currentPhotoStatus() -> OnboardingPermissionStatus {
    switch PHPhotoLibrary.authorizationStatus(for: .readWrite) {
    case .authorized:
      return .authorized
    case .limited:
      return .limited
    case .denied, .restricted:
      return .denied
    case .notDetermined:
      return .notDetermined
    @unknown default:
      return .notDetermined
    }
  }

  private func openAppSettings() {
    guard let settingsURL = URL(string: UIApplication.openSettingsURLString) else { return }
    UIApplication.shared.open(settingsURL)
  }
}
