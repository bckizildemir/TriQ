import SwiftUI

struct BadgeDetailView: View {
  @Environment(\.dismiss) private var dismiss
  let badge: Badge

  private var style: BadgeVisualStyle {
    BadgeVisualStyle(badge: badge)
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: 20) {
          BadgeIconCircle(
            badge: badge,
            circleSize: 120,
            symbolSize: 56,
            lineWidth: 2.5
          )
          .padding(.top, 24)

          Text(badge.title)
            .font(.title2.bold())
            .multilineTextAlignment(.center)
            .dynamicTypeSize(.large ... .accessibility5)

          Text(badge.description)
            .font(.body)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal)
            .dynamicTypeSize(.large ... .accessibility5)

          if badge.isLocked {
            lockedStatusCard
          } else {
            unlockedStatusCard
          }
        }
        .padding()
      }
      .navigationTitle(String(localized: "badge.details.title"))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button(String(localized: "common.done"), action: dismiss.callAsFunction)
        }
      }
    }
  }

  private var lockedStatusCard: some View {
    VStack(spacing: 10) {
      Text(badge.requirement)
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)

      ProgressView(value: badge.progress, total: 1.0)
        .tint(.accentColor)
        .frame(height: 8)
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
        .dynamicTypeSize(.large ... .accessibility5)
    }
    .padding()
    .frame(maxWidth: .infinity)
    .background {
      RoundedRectangle(cornerRadius: 12)
        .fill(Color(.secondarySystemGroupedBackground))
    }
    .padding(.horizontal)
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
      .padding(.horizontal)
  }
}

#Preview("Unlocked") {
  BadgeDetailView(
    badge: Badge(
      id: "fifty_answers",
      title: "Deneyimli",
      description: "50 soru cevapladınız. Artık bir uzman sayılırsınız!",
      icon: "crown.fill",
      isLocked: false,
      requirement: "50 soru cevaplayın",
      progress: 1.0,
      targetCount: 50,
      type: .total
    )
  )
}

#Preview("Locked") {
  BadgeDetailView(
    badge: Badge(
      id: "daily_explorer",
      title: "Günlük Kaşif",
      description: "Günlük kategorisinde 10 soru cevapladınız.",
      icon: "target",
      isLocked: true,
      requirement: "Günlük kategorisinde 10 soru cevaplayın",
      progress: 0.4,
      targetCount: 10,
      type: .category,
      category: "Daily"
    )
  )
  .preferredColorScheme(.dark)
}
