import SwiftUI

/// Persistent, untimed counterpart to the guest favorite milestone toast.
///
/// The toast confirms a single moment and disappears; this strip states the standing
/// situation for as long as it's true. It stays deliberately quieter than
/// `GuestUpgradeBannerView`: that banner is the primary call to action for the whole
/// Profile screen, while this is a status line describing the list beneath it, so it
/// wears content-level material rather than an accent tint. Corner radius is matched to
/// the question cards below so the two read as concentric rather than as competing
/// shapes.
struct GuestFavoriteStatusStrip: View {
    let count: Int
    let limit: Int
    let onUpgrade: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: "star.fill")
                .font(.footnote)
                .foregroundStyle(.yellow)
                .accessibilityHidden(true)

            Text(statusText)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button(String(localized: "guest.favorite.strip.cta"), action: onUpgrade)
                .font(.footnote.weight(.semibold))
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
                .accessibilityIdentifier("guest-favorite-strip-cta")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(
                cornerRadius: QuestionCardLayoutMetrics.compactCornerRadius,
                style: .continuous
            )
            .fill(Color(uiColor: .secondarySystemBackground))
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("guest-favorite-strip")
    }

    private var statusText: String {
        String(
            format: String(localized: "guest.favorite.strip.status"),
            locale: AppLocalization.currentLocale,
            count,
            limit
        )
    }
}

#Preview {
    VStack(spacing: 16) {
        GuestFavoriteStatusStrip(count: 3, limit: 10, onUpgrade: {})
        GuestFavoriteStatusStrip(count: 10, limit: 10, onUpgrade: {})
    }
    .padding()
}
