import CoreGraphics
import Testing
@testable import TTB

struct FavoritesScrollSettleTests {
    // An iPhone-sized scroll view under a navigation bar (top inset 100) and a home indicator
    // (bottom inset 34), 844 pt tall.
    private let topInset: CGFloat = 100
    private let bottomInset: CGFloat = 34
    private let containerHeight: CGFloat = 844

    @Test func contentThatStillFillsTheScreenNeedsNoScroll() {
        // Scrolled 200 pt into 2000 pt of content; a 300 pt card leaves 1700 pt, still far below.
        let target = FavoritesScrollSettle.target(
            contentOffsetY: 200 - topInset,
            topInset: topInset,
            bottomInset: bottomInset,
            containerHeight: containerHeight,
            newContentHeight: 1700
        )

        #expect(target == nil)
    }

    @Test func listScrolledToTheBottomSettlesOnTheNewBottom() {
        // 1200 pt of content scrolled to its bottom: scrolled distance 1200 + 100 + 34 - 844 = 490.
        // Removing a 300 pt card leaves a new bottom at 490 - 300 = 190.
        let target = FavoritesScrollSettle.target(
            contentOffsetY: 490 - topInset,
            topInset: topInset,
            bottomInset: bottomInset,
            containerHeight: containerHeight,
            newContentHeight: 900
        )

        #expect(target == 190)
    }

    @Test func listThatNowFitsTheScreenSettlesAtTheTop() {
        // Three cards, scrolled 90 pt; after the removal 600 pt of content fits the screen.
        let target = FavoritesScrollSettle.target(
            contentOffsetY: 90 - topInset,
            topInset: topInset,
            bottomInset: bottomInset,
            containerHeight: containerHeight,
            newContentHeight: 600
        )

        #expect(target == 0)
    }

    @Test func listAlreadyAtTheTopStaysAtTheTop() {
        // Not scrolled, and the content is shorter than the screen: the target is the top it is at.
        let target = FavoritesScrollSettle.target(
            contentOffsetY: -topInset,
            topInset: topInset,
            bottomInset: bottomInset,
            containerHeight: containerHeight,
            newContentHeight: 600
        )

        #expect(target == 0)
    }
}
