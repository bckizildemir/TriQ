import SwiftUI

struct BadgeView: View {
  let badge: Badge

  private var style: BadgeVisualStyle {
    BadgeVisualStyle(badge: badge)
  }

  private var progressPresentation: BadgeProgressPresentation? {
    badge.progressPresentation()
  }

  private var accessibilityLabel: String {
    badge.isLocked
      ? String(
        format: String(localized: "badge.accessibility.locked"),
        locale: AppLocalization.currentLocale,
        badge.title
      )
      : String(
        format: String(localized: "badge.accessibility.unlocked"),
        locale: AppLocalization.currentLocale,
        badge.title
      )
  }

  private var accessibilityHint: String {
    badge.isLocked
      ? String(localized: "badge.accessibility.requirementsHint")
      : String(localized: "badge.accessibility.detailsHint")
  }

  var body: some View {
    VStack(spacing: 8) {
      BadgeIconCircle(
        badge: badge,
        circleSize: 44,
        symbolSize: 21,
        lineWidth: 2
      )

      Text(badge.title)
        .font(.caption)
        .foregroundStyle(badge.isLocked ? .secondary : .primary)
        .multilineTextAlignment(.center)
        .lineLimit(2)
        .minimumScaleFactor(0.8)
        .frame(maxWidth: .infinity, minHeight: 32, alignment: .top)
        .dynamicTypeSize(.large ... .accessibility5)

      if let progressPresentation {
        Text(progressPresentation.displayText)
          .font(.caption2.weight(.medium))
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .minimumScaleFactor(0.8)
          .frame(maxWidth: .infinity, minHeight: 16)

        if progressPresentation.showsProgressBar {
          ProgressView(value: badge.progress)
            .tint(.accentColor)
            .frame(height: 4)
        } else {
          Color.clear
            .frame(height: 4)
            .accessibilityHidden(true)
        }
      } else if badge.isLocked {
        ProgressView(value: badge.progress)
          .tint(.accentColor)
          .frame(height: 4)
      } else {
        Text(String(localized: "badge.status.unlocked"))
          .font(.caption)
          .foregroundStyle(style.iconTint)
      }
    }
    .frame(minWidth: 100, minHeight: 120, alignment: .top)
    .padding(8)
    .background(Color.clear)
    .contentShape(Rectangle())
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(accessibilityLabel)
    .accessibilityValue(progressPresentation?.accessibilityValue ?? "")
    .accessibilityHint(accessibilityHint)
  }
}

#Preview("Unlocked") {
  BadgeView(
    badge: Badge(
      id: "daily_master",
      title: "Günlük Ustası",
      description: "Günlük kategorisinde 25 soru cevapladınız.",
      icon: "sun.max.fill",
      isLocked: false,
      requirement: "Günlük kategorisinde 25 soru cevaplayın",
      progress: 1.0,
      targetCount: 25,
      type: .category,
      category: "Daily"
    )
  )
}

#Preview("Locked") {
  BadgeView(
    badge: Badge(
      id: "career_focused",
      title: "Kariyer Odaklı",
      description: "Kariyer kategorisinde 10 soru cevapladınız.",
      icon: "briefcase.fill",
      isLocked: true,
      requirement: "Kariyer kategorisinde 10 soru cevaplayın",
      progress: 0.4,
      targetCount: 10,
      type: .category,
      category: "Career"
    )
  )
  .preferredColorScheme(.dark)
}
