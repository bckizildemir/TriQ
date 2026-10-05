import XCTest
@testable import TTB

@MainActor
final class AuthModelTests: XCTestCase {
    func testSignUp_rejectsMismatchedPasswords() async {
        let (model, auth, usernameService, documentManager) = makeAuthModelForTesting()
        model.email = "user@example.com"
        model.password = "password"
        model.confirmPassword = "different"
        model.username = "tester"

        await model.signUp()

        XCTAssertTrue(model.errorState.isShowing)
        XCTAssertTrue(auth.createUserCalls.isEmpty)
        XCTAssertTrue(usernameService.claimCalls.isEmpty)
        XCTAssertTrue(documentManager.deletedUserIDs.isEmpty)
    }

    func testSignUp_rejectsInvalidEmail() async {
        let (model, auth, _, _) = makeAuthModelForTesting()
        model.email = "not-an-email"
        model.password = "password"
        model.confirmPassword = "password"
        model.username = "tester"

        await model.signUp()

        XCTAssertEqual(model.errorState.message, AuthModel.AuthError.invalidEmail.localizedDescription)
        XCTAssertTrue(auth.createUserCalls.isEmpty)
    }

    func testLink_rejectsEmptyFields() async {
        let (model, _, usernameService, _) = makeAuthModelForTesting()
        await model.linkAnonymousAccount(email: "", password: "", username: "")

        XCTAssertEqual(model.errorState.message, String(localized: "auth.error.fillAllFields"))
        XCTAssertTrue(usernameService.claimCalls.isEmpty)
    }

    func testSignUp_claimUsernameFailureDeletesAccount() async {
        let (model, auth, usernameService, documentManager) = makeAuthModelForTesting()
        usernameService.claimShouldFail = true
        model.email = "user@example.com"
        model.password = "password"
        model.confirmPassword = "password"
        model.username = "tester"

        await model.signUp()

        XCTAssertEqual(documentManager.deletedUserIDs, ["created-user"])
        XCTAssertTrue(documentManager.deleteUserCalled)
        XCTAssertEqual(model.authState, .signedOut)
        XCTAssertFalse(model.showMainView)
        XCTAssertTrue(model.errorState.isShowing)
        XCTAssertEqual(auth.createUserCalls.count, 1)
    }

    func testSignUp_successSetsAuthenticated() async {
        let (model, _, usernameService, _) = makeAuthModelForTesting()
        model.email = "user@example.com"
        model.password = "password"
        model.confirmPassword = "password"
        model.username = "tester"

        await model.signUp()

        XCTAssertEqual(model.authState, .authenticated)
        XCTAssertTrue(model.showMainView)
        XCTAssertEqual(model.email, "")
        XCTAssertEqual(usernameService.claimCalls.count, 1)
        XCTAssertEqual(usernameService.claimCalls.first?.isAnonymous, false)
    }

    func testLinkAnonymous_linkFailureReleasesUsername() async {
        let auth = MockAuthProvider()
        let mockUsernameService = MockUsernameService()
        let documentManager = MockUserDocumentManager()
        documentManager.profileSnapshotResult = UserProfileSnapshot(
            username: "guest",
            email: "guest@example.com",
            isAnonymous: true
        )
        let mockUser = MockAuthUser(uid: "anon-uid", isAnonymous: true, email: nil)
        mockUser.linkShouldFail = true
        auth.currentUserValue = mockUser

        let (model, _, usernameService, _) = makeAuthModelForTesting(
            auth: auth,
            usernameService: mockUsernameService,
            userDocumentManager: documentManager
        )

        await model.linkAnonymousAccount(
            email: "user@example.com",
            password: "password",
            username: "newuser"
        )

        XCTAssertEqual(usernameService.claimCalls.count, 1)
        XCTAssertEqual(usernameService.releaseCalls.count, 1)
        XCTAssertEqual(usernameService.releaseCalls.first?.username, "newuser")
        XCTAssertEqual(usernameService.releaseCalls.first?.restoreUsername, "guest")
        XCTAssertEqual(usernameService.releaseCalls.first?.restoreEmail, "guest@example.com")
        XCTAssertEqual(usernameService.releaseCalls.first?.restoreIsAnonymous, true)
        XCTAssertTrue(model.errorState.isShowing)
    }

    func testLinkAnonymous_successClaimsTwice() async {
        let auth = MockAuthProvider()
        auth.currentUserValue = MockAuthUser(uid: "anon-uid", isAnonymous: true, email: nil)
        let (model, _, usernameService, _) = makeAuthModelForTesting(auth: auth)

        await model.linkAnonymousAccount(
            email: "user@example.com",
            password: "password",
            username: "newuser"
        )

        XCTAssertEqual(usernameService.claimCalls.count, 2)
        XCTAssertEqual(usernameService.claimCalls[0].isAnonymous, true)
        XCTAssertEqual(usernameService.claimCalls[1].isAnonymous, false)
        XCTAssertEqual(model.username, "")
        XCTAssertFalse(model.errorState.isShowing)
    }

    func testLinkAnonymous_noCurrentUserReturnsEarly() async {
        let (model, _, usernameService, _) = makeAuthModelForTesting()

        await model.linkAnonymousAccount(
            email: "user@example.com",
            password: "password",
            username: "newuser"
        )

        XCTAssertTrue(usernameService.claimCalls.isEmpty)
        XCTAssertFalse(model.isLoading)
        XCTAssertEqual(
            model.errorState.message,
            AuthModel.AuthError.userNotFound.localizedDescription
        )
    }

    func testSignIn_usernameResolvesEmail() async {
        let (model, auth, usernameService, _) = makeAuthModelForTesting()
        model.identifier = "tester"
        model.password = "password"

        await model.signIn()

        XCTAssertEqual(usernameService.resolveEmailCalls, ["tester"])
        XCTAssertEqual(auth.signInCalls.count, 1)
        XCTAssertEqual(auth.signInCalls.first?.email, "resolved@example.com")
    }

    func testSignIn_emailUsesDirectSignIn() async {
        let (model, auth, usernameService, _) = makeAuthModelForTesting()
        model.identifier = "user@example.com"
        model.password = "password"

        await model.signIn()

        XCTAssertTrue(usernameService.resolveEmailCalls.isEmpty)
        XCTAssertEqual(auth.signInCalls.count, 1)
        XCTAssertEqual(auth.signInCalls.first?.email, "user@example.com")
    }

    func testAuthListenerIgnoresStaleBootstrapAfterSignOut() async {
        let auth = MockAuthProvider()
        let documentManager = MockUserDocumentManager()
        documentManager.blockEnsure(for: "user-a")
        let (model, _, _, _) = makeAuthModelForTesting(
            auth: auth,
            userDocumentManager: documentManager,
            registersAuthListener: true
        )

        auth.emitAuthState(MockAuthUser(uid: "user-a"))
        await documentManager.waitUntilEnsureStarts(for: "user-a")

        auth.emitAuthState(nil)
        await waitForAuthState(.signedOut, on: model)

        documentManager.resumeEnsure(for: "user-a")
        await model.waitForAuthStateTasksToFinishForTesting()

        XCTAssertEqual(model.authState, .signedOut)
    }

    func testAuthListenerIgnoresStaleBootstrapAfterSwitchingUsers() async {
        let auth = MockAuthProvider()
        let documentManager = MockUserDocumentManager()
        documentManager.blockEnsure(for: "user-a")
        let (model, _, _, _) = makeAuthModelForTesting(
            auth: auth,
            userDocumentManager: documentManager,
            registersAuthListener: true
        )

        auth.emitAuthState(MockAuthUser(uid: "user-a"))
        await documentManager.waitUntilEnsureStarts(for: "user-a")

        auth.emitAuthState(MockAuthUser(uid: "user-b"))
        await waitForAuthState(.authenticated, on: model)
        XCTAssertEqual(auth.currentUser?.uid, "user-b")

        documentManager.resumeEnsure(for: "user-a")
        await model.waitForAuthStateTasksToFinishForTesting()

        XCTAssertEqual(model.authState, .authenticated)
        XCTAssertEqual(auth.currentUser?.uid, "user-b")
    }

    func testDeleteAccount_setsDeletingFlag() async {
        let deletion = MockAccountDeletionPerforming()
        let (model, _, _, _) = makeAuthModelForTesting(accountDeletionService: deletion)
        model.showMainView = true

        await model.deleteAccount(password: "secret")

        let deleteCalls = await deletion.deleteCalls
        XCTAssertEqual(deleteCalls, 1)
        XCTAssertFalse(model.showMainView)
    }

    func testDeleteAccount_ignoresDuplicateTap() async {
        let deletion = MockAccountDeletionPerforming()
        await deletion.setBlocksUntilResume(true)
        let (model, _, _, _) = makeAuthModelForTesting(accountDeletionService: deletion)

        let first = Task { await model.deleteAccount(password: "secret") }
        await deletion.waitUntilDeletionStarts()
        await model.deleteAccount(password: "secret")
        await deletion.resumePendingDeletion()
        await first.value

        let deleteCalls = await deletion.deleteCalls
        XCTAssertEqual(deleteCalls, 1)
    }

    private func waitForAuthState(_ state: AuthModel.AuthState, on model: AuthModel) async {
        for _ in 0..<100 {
            if model.authState == state {
                return
            }
            await Task.yield()
        }

        XCTFail("Timed out waiting for auth state \(state)")
    }
}
