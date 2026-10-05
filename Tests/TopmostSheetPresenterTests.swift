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
        var isPresented = true
        let lowerFlag = { isPresented = false }
        sheet.update(isPresented: isPresented, makeController: UIViewController.init, onDismissedBySystem: lowerFlag)
        let first = try #require(topmost.presentedControllers.first)

        topmost.dismissBySystem(first)
        #expect(isPresented == false, "A swiped-away sheet must lower the flag that raised it")

        sheet.update(isPresented: false, makeController: UIViewController.init, onDismissedBySystem: lowerFlag)
        sheet.update(isPresented: true, makeController: UIViewController.init, onDismissedBySystem: lowerFlag)

        #expect(topmost.presentedControllers.count == 2, "The next raise must show the sheet again")
        #expect(topmost.dismissedControllers.isEmpty, "The system already removed the first sheet")
    }

    /// UIKit refuses some presentations without an error, and the live presenter reports the
    /// sheet gone before `present` returns. The flag must still fall, or it stays raised for good.
    @Test
    func refusedPresentationLowersTheFlagAndCanPresentAgain() {
        var isPresented = true
        let lowerFlag = { isPresented = false }
        topmost.refusesPresentation = true

        sheet.update(isPresented: isPresented, makeController: UIViewController.init, onDismissedBySystem: lowerFlag)
        #expect(isPresented == false, "A refused sheet must lower the flag that raised it")

        topmost.refusesPresentation = false
        sheet.update(isPresented: true, makeController: UIViewController.init, onDismissedBySystem: lowerFlag)

        #expect(topmost.presentedControllers.count == 1, "The next raise must show the sheet")
        #expect(topmost.dismissedControllers.isEmpty, "A refused sheet has nothing to dismiss")
    }

    /// UIKit reports the disappearance of a sheet the owner itself dismissed, too. Treating that
    /// as a system dismissal would lower a flag the owner may already have raised again.
    @Test
    func dismissalTheOwnerAskedForIsNotReportedAsASystemDismissal() {
        var systemDismissals = 0
        let countSystemDismissal = { systemDismissals += 1 }
        sheet.update(isPresented: true, makeController: UIViewController.init, onDismissedBySystem: countSystemDismissal)
        sheet.update(isPresented: false, makeController: UIViewController.init, onDismissedBySystem: countSystemDismissal)

        topmost.finishDismissals()

        #expect(systemDismissals == 0)
    }

    /// "Create Free Account" closes the Upgrade Prompt and opens the upgrade sheet. UIKit refuses to
    /// present from a controller that is still being dismissed, so the second sheet must wait.
    @Test
    func followUpRunsOnlyOnceTheDismissalFinishes() {
        var followUpRan = false
        sheet.update(isPresented: true, makeController: UIViewController.init, onDismissedBySystem: {})

        sheet.dismiss { followUpRan = true }
        #expect(followUpRan == false, "The follow-up must wait for the dismissal animation")

        topmost.finishDismissals()
        #expect(followUpRan)
    }

    @Test
    func followUpRunsAtOnceWhenNoSheetIsPresented() {
        var followUpRan = false

        sheet.dismiss { followUpRan = true }

        #expect(followUpRan)
    }
}
