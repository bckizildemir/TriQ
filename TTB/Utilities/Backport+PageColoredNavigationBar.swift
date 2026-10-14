import SwiftUI

extension Backport where Content: View {
    /// Keeps the status bar and navigation bar area on `background` while content scrolls under
    /// them, before iOS 26.
    ///
    /// iOS 18 paints its grey bar material and a hairline once a scroll view under the bar
    /// scrolls (#59). Earlier versions hide that bar background and fill the area with an opaque
    /// `background` instead, through a zero-height top inset whose background extends into the
    /// safe area. iOS 26+ keeps the system bar and its scroll edge effect.
    @ViewBuilder
    func pageColoredNavigationBar(_ background: Color) -> some View {
        if #available(iOS 26.0, *) {
            content
        } else {
            content
                .safeAreaInset(edge: .top, spacing: 0) {
                    // `background(_:)` fills into the safe area by default; the view stays empty.
                    Color.clear
                        .frame(height: 0)
                        .background(background)
                        .accessibilityHidden(true)
                }
                .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
        }
    }
}
