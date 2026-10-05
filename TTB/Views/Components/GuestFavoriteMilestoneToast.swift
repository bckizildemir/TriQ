import SwiftUI

/// Turns `GuestFavoriteModel`'s one-shot milestone event into a toast.
///
/// Deliberately a single shared modifier rather than per-screen code: the inline reminder
/// this replaced was pasted into three call sites and their auto-dismiss timers had already
/// drifted apart (7s in one, 5s in the others). One owner, one behaviour.
private struct GuestFavoriteMilestoneToastModifier: ViewModifier {
    // Observed, not merely captured: `onChange` only sees a new value if this modifier's
    // body is re-evaluated when the model publishes.
    @ObservedObject var guestFavoriteModel: GuestFavoriteModel
    let toastCenter: ToastCenter

    func body(content: Content) -> some View {
        content
            .onChange(of: guestFavoriteModel.pendingFavoriteMilestone) { _, milestone in
                guard let milestone else { return }
                toastCenter.show(toast(for: milestone))
                guestFavoriteModel.clearPendingFavoriteMilestone()
            }
    }

    /// Confirms the save, then states what the guest did not already know: these are
    /// device-local, and there is a ceiling. Deliberately not actionable — a Favorite Milestone
    /// is encouragement, not the upgrade prompt, and it asks nothing of the user. The signup
    /// decision itself lives in the cap's untimed sheet and the profile's upgrade banner.
    private func toast(for milestone: GuestFavoriteMilestone) -> AppToast {
        AppToast(
            title: String(
                format: String(localized: "guest.favorite.milestone.title"),
                locale: AppLocalization.currentLocale,
                milestone.count
            ),
            subtitle: String(
                format: String(localized: "guest.favorite.milestone.subtitle"),
                locale: AppLocalization.currentLocale,
                milestone.limit
            ),
            style: .favorite,
            accessibilityIdentifier: "guest-favorite-milestone-toast",
            playsHaptic: true
        )
    }
}

extension View {
    func guestFavoriteMilestoneToast(
        guestFavoriteModel: GuestFavoriteModel,
        toastCenter: ToastCenter
    ) -> some View {
        modifier(
            GuestFavoriteMilestoneToastModifier(
                guestFavoriteModel: guestFavoriteModel,
                toastCenter: toastCenter
            )
        )
    }
}
