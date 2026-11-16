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
  /// True while the last step change went backwards; the flow view slides the other way.
  @Published private(set) var isMovingBack = false
  /// The step a request has chosen but not yet shown. The flow view commits it one render later.
  @Published private(set) var pendingStep: OnboardingStep?
  /// True from a step request until its slide ends; further requests are dropped meanwhile.
  private(set) var isChangingStep = false
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

  /// Legal acceptance only gates the final step; earlier steps just advance.
  var isPrimaryActionEnabled: Bool {
    currentStep.isFinalStep ? canComplete : !isCompleting
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
    pendingStep = nil
    isChangingStep = false
    isMovingBack = false
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
    requestStep(nextStep, movingBack: false)
  }

  func goBack() {
    guard let previousStep = currentStep.previous else { return }
    requestStep(previousStep, movingBack: true)
  }

  func skipToPermissions() {
    guard currentStep.canSkip else { return }
    requestStep(.permissions, movingBack: false)
  }

  /// Step 1 of a step change: publish the direction and the target together, without moving.
  /// SwiftUI removes a view with the transition from its last render, so the view has to render
  /// the new direction once before the step changes. The flow view reacts to `pendingStep` in
  /// `onChange`, which runs after that render, and calls `commit(_:)` inside `withAnimation`.
  /// A request is dropped while another change is in flight, until `finishStepChange()`.
  private func requestStep(_ step: OnboardingStep, movingBack: Bool) {
    guard !isChangingStep else { return }
    isChangingStep = true
    isMovingBack = movingBack
    pendingStep = step
  }

  /// Step 2: show the requested step. Call it inside `withAnimation`.
  func commit(_ step: OnboardingStep) {
    pendingStep = nil
    currentStep = step
  }

  /// Step 3: the slide ended; taps are accepted again.
  func finishStepChange() {
    isChangingStep = false
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
