import SwiftUI

extension Backport where Content: View {
    /// Pins `bar` to the top edge and insets the safe area by its height.
    ///
    /// iOS 26+ uses `safeAreaBar(edge: .top)`, which also extends the scroll edge effect under
    /// the bar. Earlier versions use `safeAreaInset(edge: .top)` on an opaque
    /// `fallbackBackground`. That background also fills the status bar and navigation bar
    /// area, so content that scrolls up is hidden behind it. The navigation bar background is
    /// hidden there: without that, iOS 18 paints its grey material and hairline over the bar
    /// once the content scrolls (#59).
    @ViewBuilder
    func safeAreaBarOnTop(
        fallbackBackground: Color,
        @ViewBuilder content bar: () -> some View
    ) -> some View {
        if #available(iOS 26.0, *) {
            content.safeAreaBar(edge: .top, content: bar)
        } else {
            content
                .safeAreaInset(edge: .top) {
                    bar()
                        .frame(maxWidth: .infinity)
                        .background(fallbackBackground)
                }
                .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
        }
    }
}
