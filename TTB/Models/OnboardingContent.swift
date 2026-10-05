import Foundation

struct OnboardingContent {
  static var welcomeTitle: String { String(localized: "onboarding.welcome.title") }
  static var welcomeBody: String { String(localized: "onboarding.welcome.body") }
  static var welcomeTags: [String] {
    [
      String(localized: "onboarding.welcome.tags.1"),
      String(localized: "onboarding.welcome.tags.2"),
      String(localized: "onboarding.welcome.tags.3")
    ]
  }

  static var sampleTitle: String { String(localized: "onboarding.welcome.sampleTitle") }
  static var sampleBody: String { String(localized: "onboarding.welcome.sampleBody") }
  static var sampleQuestion: String { String(localized: "onboarding.welcome.sampleQuestion") }
  static var sampleAnswers: [String] {
    [
      String(localized: "onboarding.welcome.sampleAnswers.1"),
      String(localized: "onboarding.welcome.sampleAnswers.2"),
      String(localized: "onboarding.welcome.sampleAnswers.3")
    ]
  }

  static var sampleAnswerSymbols: [String] {
    ["tv.fill", "leaf.fill", "figure.climbing"]
  }

  static var sharingTitle: String { String(localized: "onboarding.sharing.title") }
  static var sharingBody: String { String(localized: "onboarding.sharing.body") }
  static var sharingQuestion: String { String(localized: "onboarding.sharing.question") }
  static var sharingLeftTitle: String { String(localized: "onboarding.sharing.leftTitle") }
  static var sharingRightTitle: String { String(localized: "onboarding.sharing.rightTitle") }
  static var sharingLeftAnswers: [String] {
    [
      String(localized: "onboarding.sharing.leftAnswers.1"),
      String(localized: "onboarding.sharing.leftAnswers.2"),
      String(localized: "onboarding.sharing.leftAnswers.3")
    ]
  }
  static var sharingRightAnswers: [String] {
    [
      String(localized: "onboarding.sharing.rightAnswers.1"),
      String(localized: "onboarding.sharing.rightAnswers.2"),
      String(localized: "onboarding.sharing.rightAnswers.3")
    ]
  }

  static var valueTitle: String { String(localized: "onboarding.value.title") }
  static var valueBody: String { String(localized: "onboarding.value.body") }
  static var valueHighlights: [String] {
    [
      String(localized: "onboarding.value.highlight.1"),
      String(localized: "onboarding.value.highlight.2"),
      String(localized: "onboarding.value.highlight.3")
    ]
  }

  static var guestFeatureTitle: String { String(localized: "onboarding.welcome.guestFeatureTitle") }
  static var guestFeatureBody: String { String(localized: "onboarding.welcome.guestFeatureBody") }

  static var accountFeatureTitle: String { String(localized: "onboarding.welcome.accountFeatureTitle") }
  static var accountFeatureBody: String { String(localized: "onboarding.welcome.accountFeatureBody") }

  static var permissionsTitle: String { String(localized: "onboarding.permissions.title") }
  static var permissionsBody: String { String(localized: "onboarding.permissions.body") }

  static var notificationsTitle: String { String(localized: "onboarding.permissions.notifications.title") }
  static var notificationsBody: String { String(localized: "onboarding.permissions.notifications.body") }

  static var photosTitle: String { String(localized: "onboarding.permissions.photos.title") }
  static var photosBody: String { String(localized: "onboarding.permissions.photos.body") }

  static var legalPrefix: String { String(localized: "onboarding.legal.prefix") }
  static var legalMiddle: String { String(localized: "onboarding.legal.middle") }
  static var legalSuffix: String { String(localized: "onboarding.legal.suffix") }
  static var legalInlinePrefix: String { String(localized: "onboarding.legal.inlinePrefix") }
  static var legalInlineSuffix: String { String(localized: "onboarding.legal.inlineSuffix") }
}
