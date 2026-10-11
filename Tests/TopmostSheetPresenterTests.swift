import Testing
import UIKit
@testable import TTB

/// The rules the Upgrade Prompt's single owner follows (ADR 0010), checked against a fake window
/// instead of UIKit. A raised flag shows exactly one sheet, and a sheet that goes away on its own
/// lowers the flag again — otherwise the flag stays raised and the prompt never shows twice.
@MainActor
struct TopmostSheetPresenterTests {
    private let topmost = FakeTopmostPresenter()
    private let sheet: TopmostSheetPresenter

    init() {
        sheet = TopmostSheetPresenter(presenter: topmost)
    }

    @Test
    func raisedFlagPresentsTheSheetOnce() {
        sheet.update(isPresented: true, makeController: UIViewController.init, onDismissedBySystem: {})
        sheet.update(isPresented: true, makeController: UIViewController.init, onDismissedBySystem: {})

        #expect(topmost.presentedControllers.count == 1, "A flag that stays raised must not stack a second sheet")
    }

    @Test
    func loweredFlagDismissesThePresentedSheet() throws {
        sheet.update(isPresented: true, makeController: UIViewController.init, onDismissedBySystem: {})
        let presented = try #require(topmost.presentedControllers.first)

        sheet.update(isPresented: false, makeController: UIViewController.init, onDismissedBySystem: {})

        #expect(topmost.dismissedControllers == [presented])
    }

    @Test
    func sheetThatGoesAwayOnItsOwnLowersTheFlagAndCanPresentAgain() throws {
        let flag = FlagBox(raised: true)
        let lowerFlag: @MainActor @Sendable () -> Void = { flag.raised = false }
        sheet.update(isPresented: flag.raised, makeController: UIViewController.init, onDismissedBySystem: lowerFlag)
        let first = try #require(topmost.presentedControllers.first)

        topmost.dismissBySystem(first)
        #expect(flag.raised == false, "A swiped-away sheet must lower the flag that raised it")

        sheet.update(isPresented: false, makeController: UIViewController.init, onDismissedBySystem: lowerFlag)
        sheet.update(isPresented: true, makeController: UIViewController.init, onDismissedBySystem: lowerFlag)

        #expect(topmost.presentedControllers.count == 2, "The next raise must show the sheet again")
        #expect(topmost.dismissedControllers.isEmpty, "The system already removed the first sheet")
    }

    /// UIKit refuses some presentations without an error, and the live presenter reports the
    /// sheet gone before `present` returns. The flag must still fall, or it stays raised for good.
    @Test
    func refusedPresentationLowersTheFlagAndCanPresentAgain() {
        let flag = FlagBox(raised: true)
        let lowerFlag: @MainActor @Sendable () -> Void = { flag.raised = false }
        topmost.refusesPresentation = true

        sheet.update(isPresented: flag.raised, makeController: UIViewController.init, onDismissedBySystem: lowerFlag)
        #expect(flag.raised == false, "A refused sheet must lower the flag that raised it")

        topmost.refusesPresentation = false
        sheet.update(isPresented: true, makeController: UIViewController.init, onDismissedBySystem: lowerFlag)

        #expect(topmost.presentedControllers.count == 1, "The next raise must show the sheet")
        #expect(topmost.dismissedControllers.isEmpty, "A refused sheet has nothing to dismiss")
    }

    /// UIKit reports the disappearance of a sheet the owner itself dismissed, too. Treating that
    /// as a system dismissal would lower a flag the owner may already have raised again.
    @Test
    func dismissalTheOwnerAskedForIsNotReportedAsASystemDismissal() {
        let counter = CallCounter()
        let countSystemDismissal: @MainActor @Sendable () -> Void = { counter.count += 1 }
        sheet.update(isPresented: true, makeController: UIViewController.init, onDismissedBySystem: countSystemDismissal)
        sheet.update(isPresented: false, makeController: UIViewController.init, onDismissedBySystem: countSystemDismissal)

        topmost.finishDismissals()

        #expect(counter.count == 0)
    }

    /// "Create Free Account" closes the Upgrade Prompt and opens the upgrade sheet. UIKit refuses to
    /// present from a controller that is still being dismissed, so the second sheet must wait.
    @Test
    func followUpRunsOnlyOnceTheDismissalFinishes() {
        let followUp = FlagBox(raised: false)
        sheet.update(isPresented: true, makeController: UIViewController.init, onDismissedBySystem: {})

        sheet.dismiss { followUp.raised = true }
        #expect(followUp.raised == false, "The follow-up must wait for the dismissal animation")

        topmost.finishDismissals()
        #expect(followUp.raised)
    }

    @Test
    func followUpRunsAtOnceWhenNoSheetIsPresented() {
        let followUp = FlagBox(raised: false)

        sheet.dismiss { followUp.raised = true }

        #expect(followUp.raised)
    }
}

/// Reference-typed flag the `@Sendable` closures of the presenter can capture. A captured local
/// `var` is a data-race error in the Swift 6 language mode.
@MainActor
private final class FlagBox {
    var raised: Bool

    init(raised: Bool) {
        self.raised = raised
    }
}

/// Counts how often a `@Sendable` presenter callback ran, for the same capture reason as `FlagBox`.
@MainActor
private final class CallCounter {
    var count = 0
}
