import SwiftUI

struct OnboardingPermissionCard: View {
  let title: String
  let message: String
  let status: OnboardingPermissionStatus
  let action: () -> Void

  private var isGranted: Bool {
    status == .authorized || status == .limited
  }

  private var showsActionButton: Bool {
    !isGranted
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text(title)
          .font(.headline)

        Spacer()

        statusIndicator
      }

      Text(message)
        .font(.subheadline)
        .foregroundStyle(.secondary)

      if showsActionButton {
        AuthSecondaryChipButton(
          title: status.actionTitle,
          isLoading: false,
          loadingAccessibilityLabel: status.actionTitle
        ) {
          action()
        }
      }
    }
    .padding(16)
    .background(
      RoundedRectangle(cornerRadius: 22)
        .fill(Color.theme.secondaryBackground)
        .overlay(
          RoundedRectangle(cornerRadius: 22)
            .stroke(Color.theme.border.opacity(0.22), lineWidth: 1)
        )
    )
  }

  @ViewBuilder
  private var statusIndicator: some View {
    switch status {
    case .authorized, .limited:
      Image(systemName: "checkmark.circle.fill")
        .font(.body)
        .foregroundStyle(.green)
        .accessibilityLabel(status.badgeText)
    case .denied:
      Text(status.badgeText)
        .font(.caption.weight(.semibold))
        .foregroundStyle(.orange)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.orange.opacity(0.12), in: Capsule())
    case .notDetermined:
      EmptyView()
    }
  }
}
