import SwiftUI

/// A list row for a create the server has not confirmed. With no actions it is inert, which is how
/// the question picker shows it: such a list cannot take questions.
struct PendingListRowView: View {
    let pending: PendingListCreation
    var onRetry: (() -> Void)?
    var onDelete: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(pending.name)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.secondary)

                HStack(spacing: 6) {
                    if pending.state == .saving {
                        ProgressView()
                            .accessibilityHidden(true)
                    }
                    Text(pending.state.title)
                        .font(.subheadline)
                        .foregroundStyle(pending.state == .failed ? Color.red : Color.secondary)
                }
            }

            if pending.state == .failed, let onRetry, let onDelete {
                Spacer()

                Button(String(localized: "common.retry"), action: onRetry)
                    .buttonStyle(.borderless)
                    .accessibilityIdentifier("pending-list-retry-\(pending.id)")

                Button(String(localized: "common.delete"), role: .destructive, action: onDelete)
                    .buttonStyle(.borderless)
                    .accessibilityIdentifier("pending-list-delete-\(pending.id)")
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("pending-list-row-\(pending.id)")
    }
}
