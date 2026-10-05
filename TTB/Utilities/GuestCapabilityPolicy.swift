import Foundation

enum GuestCapabilityPolicy {
  static func canAccessProfilePhoto(isAnonymous: Bool) -> Bool {
    !isAnonymous
  }

  static func canAccessBadgesAndProgress(isAnonymous: Bool) -> Bool {
    !isAnonymous
  }

  static func dailyAILimit(isAnonymous: Bool) -> Int {
    isAnonymous ? AppConfig.guestDailyAIQueryLimit : 20
  }
}
