import Foundation

enum OnboardingPermissionStatus {
  case notDetermined
  case authorized
  case limited
  case denied

  var badgeText: String {
    switch self {
    case .notDetermined:
      String(localized: "onboarding.status.notDetermined")
    case .authorized:
      String(localized: "onboarding.status.authorized")
    case .limited:
      String(localized: "onboarding.status.limited")
    case .denied:
      String(localized: "onboarding.status.denied")
    }
  }

  var actionTitle: String {
    switch self {
    case .notDetermined:
      String(localized: "onboarding.button.requestPermission")
    case .authorized, .limited:
      String(localized: "onboarding.button.opened")
    case .denied:
      String(localized: "onboarding.button.openSettings")
    }
  }
}
