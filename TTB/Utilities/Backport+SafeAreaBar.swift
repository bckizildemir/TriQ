import SwiftUI

extension Backport where Content: View {
    /// Pins `bar` to a vertical edge and insets the safe area by its height.
    ///
    /// iOS 26+ uses `safeAreaBar(edge:)`, which also extends the scroll edge effect under the
    /// bar. Earlier versions use `safeAreaInset(edge:)` with a `.bar` background, so content
    /// that scrolls under the bar stays readable.
    @ViewBuilder
    func safeAreaBar(
        edge: VerticalEdge,
        @ViewBuilder content bar: () -> some View
    ) -> some View {
        if #available(iOS 26.0, *) {
            content.safeAreaBar(edge: edge, content: bar)
        } else {
            content.safeAreaInset(edge: edge) {
                bar()
                    .frame(maxWidth: .infinity)
                    .background(.bar)
            }
        }
    }
}
