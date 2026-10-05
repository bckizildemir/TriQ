import Foundation

enum OnboardingStep: Int, CaseIterable {
  case welcome
  case example
  case value
  case sharing
  case permissions

  var progressValue: Double {
    Double(rawValue + 1) / Double(Self.allCases.count)
  }

  var isFinalStep: Bool {
    self == .permissions
  }

  var canSkip: Bool {
    !isFinalStep
  }

  var next: OnboardingStep? {
    Self(rawValue: rawValue + 1)
  }

  var previous: OnboardingStep? {
    Self(rawValue: rawValue - 1)
  }
}
