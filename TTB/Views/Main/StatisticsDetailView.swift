import SwiftUI

struct StatisticsDetailView: View {
    let statistics: ProfileModel.Statistics

    private var isEmpty: Bool {
        statistics.daily == 0 && statistics.weekly == 0 && statistics.total == 0
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    HStack(spacing: 12) {
                        StatisticCard(
                            title: String(localized: "profile.statistics.today"),
                            value: "\(statistics.daily)",
                            icon: "calendar",
                            color: .blue
                        )
                        StatisticCard(
                            title: String(localized: "profile.statistics.week"),
                            value: "\(statistics.weekly)",
                            icon: "calendar.badge.clock",
                            color: .purple
                        )
                        StatisticCard(
                            title: String(localized: "profile.statistics.total"),
                            value: "\(statistics.total)",
                            icon: "chart.bar.fill",
                            color: .green
                        )
                    }
                    .padding(.horizontal, 20)

                    if isEmpty {
                        ContentUnavailableView(
                            String(localized: "profile.statistics.emptyTitle"),
                            systemImage: "chart.bar.xmark",
                            description: Text(String(localized: "profile.statistics.emptyBody"))
                        )
                        .padding(.top, 16)
                    }
                }
                .padding(.top, 24)
                .padding(.bottom, 32)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(String(localized: "profile.section.statistics"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    SimulatorSafeSheetDismissButton {
                        Image(systemName: "xmark.circle.fill")
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.secondary)
                            .font(.title2)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel(String(localized: "common.close"))
                    .accessibilityHint(String(localized: "profile.statistics.closeHint"))
                    .accessibilityIdentifier("profile-statistics-close-button")
                }
            }
        }
    }
}

#Preview("İstatistikler — Boş") {
    StatisticsDetailView(statistics: .init())
}

#Preview("İstatistikler — Dolu") {
    StatisticsDetailView(statistics: .init(daily: 3, weekly: 14, total: 87))
}
