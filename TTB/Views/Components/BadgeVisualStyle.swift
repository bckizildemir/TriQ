import SwiftUI

struct BadgeVisualStyle {
  enum Context {
    case live
    case adminPreview
  }

  enum Palette: String {
    case neutral
    case accent
    case yellow
    case orange
    case pink
    case indigo
    case purple
    case mint

    var color: Color {
      switch self {
      case .neutral:
        return Color(.systemGray3)
      case .accent:
        return .accentColor
      case .yellow:
        return .yellow
      case .orange:
        return .orange
      case .pink:
        return .pink
      case .indigo:
        return .indigo
      case .purple:
        return .purple
      case .mint:
        return .mint
      }
    }
  }

  let palette: Palette
  let iconTint: Color
  let circleFill: Color
  let circleStroke: Color
  let usesTintedUnlockedBackground: Bool

  init(badge: Badge, context: Context = .live) {
    let treatsAsLocked = Self.treatsBadgeAsLocked(badge, context: context)
    let palette = Self.palette(for: badge.icon, isLocked: treatsAsLocked)

    self.palette = palette
    usesTintedUnlockedBackground = !treatsAsLocked

    if treatsAsLocked {
      iconTint = Color(.systemGray3)
      circleFill = Color(.systemGray6)
      circleStroke = Color(.systemGray4).opacity(0.7)
    } else {
      let baseColor = palette.color
      iconTint = baseColor
      circleFill = baseColor.opacity(0.18)
      circleStroke = baseColor.opacity(0.6)
    }
  }

  static func treatsBadgeAsLocked(_ badge: Badge, context: Context) -> Bool {
    switch context {
    case .live:
      return badge.isLocked
    case .adminPreview:
      return false
    }
  }

  static func palette(for icon: String, isLocked: Bool) -> Palette {
    guard !isLocked else { return .neutral }

    switch icon {
    case "sun.max.fill", "crown.fill", "star.fill", "star.circle.fill", "trophy.fill", "medal.fill":
      return .yellow
    case "flame.fill", "flame.circle.fill", "flame.circle", "bolt.fill", "bolt.circle.fill":
      return .orange
    case "heart.fill", "heart.circle.fill":
      return .pink
    case "briefcase.fill", "building.2.fill", "flag.fill", "scope", "target", "1.circle.fill",
      "5.circle.fill":
      return .indigo
    case "paintbrush.fill", "paintpalette.fill", "wand.and.stars", "sparkles":
      return .purple
    case "heart.text.square.fill", "cross.circle.fill", "person.fill.checkmark",
      "figure.mind.and.body", "graduationcap.fill", "checkmark.shield.fill":
      return .mint
    default:
      return .accent
    }
  }
}
