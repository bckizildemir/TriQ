import Testing
@testable import TTB

/// The profile screen offers "Try Again" only for an error that came from account deletion
/// (TriQ#88), so `AuthModel` marks that error.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct AuthModelAccountDeletionFailureTests {
    @Test func failedDeletionIsMarkedAsADeletionFailure() async {
        let deletion = MockAccountDeletionPerforming()
        await deletion.setShouldFail(true)
        let (model, _, _, _) = makeAuthModelForTesting(accountDeletionService: deletion)

        await model.deleteAccount(password: nil)

        #expect(model.errorState.isShowing)
        #expect(model.errorState.isAccountDeletionFailure)
    }

    @Test func dismissingTheErrorClearsTheMark() async {
        let deletion = MockAccountDeletionPerforming()
        await deletion.setShouldFail(true)
        let (model, _, _, _) = makeAuthModelForTesting(accountDeletionService: deletion)
        await model.deleteAccount(password: nil)

        model.dismissError()

        #expect(!model.errorState.isAccountDeletionFailure)
    }

    @Test func retryAfterAFailureSucceeds() async {
        let deletion = MockAccountDeletionPerforming()
        await deletion.setShouldFail(true)
        let (model, _, _, _) = makeAuthModelForTesting(accountDeletionService: deletion)
        model.showMainView = true
        await model.deleteAccount(password: nil)

        await deletion.setShouldFail(false)
        model.dismissError()
        await model.deleteAccount(password: nil)

        #expect(await deletion.deleteCalls == 2)
        #expect(!model.errorState.isShowing)
        #expect(!model.showMainView)
    }
}
