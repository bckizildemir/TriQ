import CoreGraphics

/// Where the Favorites list scrolls when a removal makes its content shorter.
///
/// When the shorter content no longer reaches the bottom of the visible area, the scroll view
/// would pull its offset back in a single frame, before the cards finish sliding up.
/// `FavoritesContentView` holds the old content height for a moment, scrolls to this target in
/// the same animation as the slide, and only then lets the content shrink.
enum FavoritesScrollSettle {
    /// The scrolled distance to animate to, where 0 is the top of the content, or `nil` when the
    /// shorter content still fills the visible area and nothing needs to scroll.
    ///
    /// - Parameters:
    ///   - contentOffsetY: `ScrollGeometry.contentOffset.y`; negative at the top when there is a
    ///     top inset.
    ///   - topInset: `ScrollGeometry.contentInsets.top`.
    ///   - bottomInset: `ScrollGeometry.contentInsets.bottom`.
    ///   - containerHeight: `ScrollGeometry.containerSize.height`.
    ///   - newContentHeight: the content's height after the removal.
    static func target(
        contentOffsetY: CGFloat,
        topInset: CGFloat,
        bottomInset: CGFloat,
        containerHeight: CGFloat,
        newContentHeight: CGFloat
    ) -> CGFloat? {
        let visibleBottom = contentOffsetY + containerHeight
        let lowestReachableBottom = newContentHeight + bottomInset
        let overshoot = visibleBottom - lowestReachableBottom
        guard overshoot > 0.5 else { return nil }

        let scrolledDistance = contentOffsetY + topInset
        return max(0, scrolledDistance - overshoot)
    }
}
