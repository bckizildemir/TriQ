import SwiftUI

struct AdminToolsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ProfileSectionHeader(title: String(localized: "admin.tools.title"))

            VStack(spacing: 0) {
                adminLink(
                    route: .questions,
                    icon: "questionmark.bubble",
                    iconColor: .blue,
                    title: String(localized: "admin.tools.questions")
                )

                Divider()
                    .padding(.leading, 76)

                adminLink(
                    route: .categories,
                    icon: "square.grid.2x2",
                    iconColor: .orange,
                    title: String(localized: "admin.tools.categories")
                )

                Divider()
                    .padding(.leading, 76)

                adminLink(
                    route: .badges,
                    icon: "star.fill",
                    iconColor: .yellow,
                    title: String(localized: "admin.tools.badges")
                )

                Divider()
                    .padding(.leading, 76)

                adminLink(
                    route: .releases,
                    icon: "megaphone.fill",
                    iconColor: .green,
                    title: String(localized: "admin.tools.releases")
                )
            }
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 16)
        }
    }

    private func adminLink(
        route: AdminRoute,
        icon: String,
        iconColor: Color,
        title: String
    ) -> some View {
        NavigationLink(value: route) {
            SettingsRowView(
                icon: icon,
                iconColor: iconColor,
                title: title
            )
            .padding(.horizontal, 20)
        }
        .buttonStyle(ScaleButtonStyle())
    }
}
