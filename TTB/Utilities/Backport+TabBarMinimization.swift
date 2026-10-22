import SwiftUI

extension Backport where Content: View {
    /// Minimizes the tab bar while the user scrolls down and restores it when they scroll back
    /// up or tap the minimized bar. Apply it to the `TabView`.
    ///
    /// iOS 26+ only; earlier versions keep the full-height bar.
    @ViewBuilder
    func minimizesTabBarOnScrollDown() -> some View {
        if #available(iOS 26.0, *) {
            content.tabBarMinimizeBehavior(.onScrollDown)
        } else {
            content
        }
    }
}
