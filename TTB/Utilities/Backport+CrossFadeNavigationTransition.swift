import SwiftUI

extension Backport where Content: View {
    /// Makes the sheet or cover this view roots fade in and out instead of sliding.
    ///
    /// iOS 27+ only; earlier versions keep the standard presentation.
    @ViewBuilder
    func crossFadeNavigationTransition() -> some View {
        // `crossFade` is new in the iOS 27 SDK, which ships with Swift 6.4 (Xcode 27). CI may
        // still build with Xcode 26, where the symbol does not exist.
        #if compiler(>=6.4)
        if #available(iOS 27.0, *) {
            content.navigationTransition(.crossFade)
        } else {
            content
        }
        #else
        content
        #endif
    }
}
