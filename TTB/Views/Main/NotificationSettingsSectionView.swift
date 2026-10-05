import SwiftUI

struct NotificationSettingsSectionView: View {
    @EnvironmentObject private var notificationService: NotificationService

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "profile.section.notifications"))
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .padding(.horizontal, 20)

            VStack(spacing: 0) {
                Toggle(isOn: toggleBinding) {
                    Text(String(localized: "profile.notifications.contentUpdates"))
                        .font(.body)
                }
                .toggleStyle(.switch)
                .padding(.vertical, 12)
                .padding(.horizontal, 20)
            }
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 16)

            VStack(alignment: .leading, spacing: 8) {
                Text(statusDescription)
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                if notificationService.authorizationStatus == .denied {
                    Button(String(localized: "profile.notifications.openSettings")) {
                        notificationService.openSystemSettings()
                    }
                    .font(.footnote.weight(.semibold))
                }
            }
            .padding(.horizontal, 20)
        }
    }

    private var toggleBinding: Binding<Bool> {
        Binding(
            get: { notificationService.contentUpdatesEnabled },
            set: { newValue in
                Task {
                    if newValue && notificationService.authorizationStatus != .authorized {
                        do {
                            let granted = try await notificationService.requestAuthorization()
                            guard granted else {
                                await notificationService.updateContentUpdatesEnabled(false)
                                return
                            }
                        } catch {
                            return
                        }
                    }

                    await notificationService.updateContentUpdatesEnabled(newValue)
                }
            }
        )
    }

    private var statusDescription: String {
        switch notificationService.authorizationStatus {
        case .authorized:
            return String(localized: "profile.notifications.status.authorized")
        case .denied:
            return String(localized: "profile.notifications.status.denied")
        case .notDetermined:
            return String(localized: "profile.notifications.status.notDetermined")
        }
    }
}
