import XCTest
@testable import TTB

final class BadgeVisualStyleTests: XCTestCase {

  func testKnownSymbolPaletteMappings() {
    XCTAssertEqual(BadgeVisualStyle.palette(for: "sun.max.fill", isLocked: false), .yellow)
    XCTAssertEqual(BadgeVisualStyle.palette(for: "crown.fill", isLocked: false), .yellow)
    XCTAssertEqual(BadgeVisualStyle.palette(for: "heart.fill", isLocked: false), .pink)
    XCTAssertEqual(BadgeVisualStyle.palette(for: "briefcase.fill", isLocked: false), .indigo)
  }

  func testUnknownSymbolFallsBackToAccentPalette() {
    XCTAssertEqual(BadgeVisualStyle.palette(for: "paperplane.fill", isLocked: false), .accent)
  }

  func testLockedBadgesAlwaysUseNeutralPalette() {
    let lockedBadge = Badge(
      id: "daily_master",
      title: "Günlük Ustası",
      description: "Günlük kategorisinde 25 soru cevapladınız.",
      icon: "sun.max.fill",
      isLocked: true,
      requirement: "Günlük kategorisinde 25 soru cevaplayın",
      progress: 0.25,
      targetCount: 25,
      type: .category,
      category: "Daily"
    )

    let style = BadgeVisualStyle(badge: lockedBadge)

    XCTAssertEqual(style.palette, .neutral)
    XCTAssertFalse(style.usesTintedUnlockedBackground)
  }

  func testAdminPreviewTreatsLockedBadgeAsUnlocked() {
    let badge = Badge(
      id: "career_focused",
      title: "Career Focused",
      description: "Answer 10 career questions.",
      icon: "briefcase.fill",
      isLocked: true,
      requirement: "Answer 10 career questions",
      progress: 0.3,
      targetCount: 10,
      type: .category,
      category: "Career"
    )

    let style = BadgeVisualStyle(badge: badge, context: .adminPreview)

    XCTAssertEqual(style.palette, .indigo)
    XCTAssertTrue(style.usesTintedUnlockedBackground)
    XCTAssertFalse(BadgeVisualStyle.treatsBadgeAsLocked(badge, context: .adminPreview))
  }
}
