import SwiftUI

struct BadgeDetailSheet: View {
  let badge: Badge

  private var style: BadgeVisualStyle {
    BadgeVisualStyle(badge: badge)
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: 24) {
          BadgeIconCircle(
            badge: badge,
            circleSize: 100,
            symbolSize: 52,
            lineWidth: 2
          )
          .padding(.top, 24)

          VStack(spacing: 16) {
            Text(badge.title)
              .font(.title2.bold())
              .multilineTextAlignment(.center)

            Text(badge.description)
              .font(.body)
              .foregroundStyle(.secondary)
              .multilineTextAlignment(.center)

            if badge.isLocked {
              lockedStatusCard
            } else {
              unlockedStatusCard
            }
          }
          .padding(.horizontal)
        }
      }
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          SimulatorSafeSheetDismissButton {
            Text(String(localized: "common.done"))
          }
        }
      }
    }
    .accessibilityElement(children: .contain)
    .accessibilityLabel(
      String(
        format: String(localized: "badge.accessibility.detailsLabel"),
        locale: AppLocalization.currentLocale,
        badge.title
      )
    )
    .accessibilityHint(badge.description)
  }

  private var lockedStatusCard: some View {
    VStack(spacing: 8) {
      Text(badge.requirement)
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)

      ProgressView(value: badge.progress)
        .tint(.accentColor)
        .frame(height: 6)
        .padding(.horizontal)
        .accessibilityValue(
          AppLocalization.prefersEnglish
            ? "\(Int(badge.progress * 100))% complete"
            : "%\(Int(badge.progress * 100)) tamamlandı"
        )

      Text(
        AppLocalization.prefersEnglish
          ? "\(Int(badge.progress * 100))% Complete"
          : "%\(Int(badge.progress * 100)) Tamamlandı"
      )
        .font(.caption)
        .foregroundStyle(.secondary)
    }
    .padding()
    .background {
      RoundedRectangle(cornerRadius: 12)
        .fill(Color(.secondarySystemGroupedBackground))
    }
  }

  private var unlockedStatusCard: some View {
    Label(String(localized: "badge.status.unlockedTitle"), systemImage: "checkmark.circle.fill")
      .font(.headline)
      .foregroundStyle(style.iconTint)
      .padding()
      .frame(maxWidth: .infinity)
      .background {
        RoundedRectangle(cornerRadius: 12)
          .fill(style.circleFill)
      }
  }
}

#Preview("Unlocked") {
  BadgeDetailSheet(
    badge: Badge(
      id: "daily_master",
      title: "Günlük Ustası",
      description: "Günlük kategorisinde 25 soru cevapladınız. Gününüze yön veriyorsunuz!",
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
  BadgeDetailSheet(
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
