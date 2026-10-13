import SwiftUI

extension Backport where Content: View {
    /// Minimizes the navigation bar while the user scrolls down and restores it when the
    /// scroll direction reverses. Apply it beside `.navigationChromeTitle(...)` on a
    /// stack root.
    ///
    /// iOS 27+ only: `ToolbarMinimizationBehavior` does not exist earlier, so the shim takes
    /// no parameter and earlier versions keep a full-height bar.
    // `@ViewBuilder`, not `@ContentBuilder`, and the compiler check: CI builds with the
    // Xcode 26 SDK, which has neither the builder name nor the iOS 27 modifier.
    @ViewBuilder
    func minimizesNavigationBarOnScrollDown() -> some View {
        #if compiler(>=6.4)
        if #available(iOS 27.0, *) {
            content.toolbarMinimizationBehavior(.onScrollDown, for: .navigationBar)
        } else {
            content
        }
        #else
        content
        #endif
    }
}
