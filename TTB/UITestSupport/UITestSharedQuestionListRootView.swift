import SwiftUI

#if DEBUG
/// Shared question lists: the hub over the main tabs, the accept flow, and the owner's share detail.
///
/// Three tests share one fixture set, so the body picks a screen and `appRoot(_:)` supplies
/// everything around it. The two deep-link sheets used to be declared here as well, each
/// re-injecting nine environment objects — that is what the modifier replaced.
struct UITestSharedQuestionListRootView: View {
    private static let recipientUserId = "ui-test-recipient"
    private static let shareCode = "ui-test-share-code"
    private static let shareId = "ui-test-share"
    private static let compareShareCode = "ui-test-compare-share-code"
    private static let compareShareId = "ui-test-compare-share"
    private static let compareRecipientId = "ui-test-compare-recipient"
    private static let questionId = "ui-test-shared-question"
    private static let listId = "ui-test-owned-list"
    private static let categoryId = "Career"
    private static let storage = UserDefaults.harnessSuite(named: "UITestSharedQuestionListRootView")
    /// Now that `SharedQuestionListStore` no longer caches accepted-share IDs (issue #24), the
    /// harness has to reproduce relaunch persistence itself: the in-memory adapter it seeds is
    /// rebuilt from scratch on every launch, so without this the accept flow's result would not
    /// survive `testAcceptedSharedQuestionListPersistsAfterRelaunch`'s `app.terminate()`.
    private static let acceptedShareIDsKey = "uiTestAcceptedShareIDs"

    @StateObject private var environment: AppEnvironment
    /// `AppRootBehaviourModifier` only observes four models on `environment` and this view's own
    /// body never reads `environment.sharedQuestionListStore`, so without observing the store
    /// directly here too, an accept made through the deep-link sheet would not trigger a re-render
    /// of this view and the `onChange` below would never see it.
    @StateObject private var sharedQuestionListStore: SharedQuestionListStore

    init() {
        if UITestLaunchOptions.shouldResetSharedQuestionListHarness {
            Self.storage.removeObject(forKey: Self.acceptedShareIDsKey)
        }

        let persistedAcceptedShareIDs = Set(Self.storage.stringArray(forKey: Self.acceptedShareIDsKey) ?? [])
        let localAcceptedShares = persistedAcceptedShareIDs.contains(Self.shareId)
            ? [Self.acceptedShareFixture]
            : []

        let sharedQuestionListStore = SharedQuestionListStore(
            localOwnedShares: [Self.compareShareFixture, Self.shareFixture],
            localAcceptedShares: localAcceptedShares,
            localRecipientsByShareID: [
                Self.compareShareId: [Self.compareRecipientFixture]
            ],
            localUserId: Self.recipientUserId
        )
        _sharedQuestionListStore = StateObject(wrappedValue: sharedQuestionListStore)

        _environment = StateObject(
            wrappedValue: .uiTest(
                storage: Self.storage,
                authModel: UITestAuthModelFactory.permanentUser(uid: Self.recipientUserId),
                questionModel: QuestionModel(localQuestions: [Self.questionFixture]),
                profileModel: ProfileModel(
                    userId: Self.recipientUserId,
                    startsAuthListener: false,
                    loadsRemoteData: false
                ),
                questionListStore: QuestionListStore(localLists: [Self.listFixture]),
                sharedQuestionListStore: sharedQuestionListStore
            )
        )
    }

    var body: some View {
        screen
            .appRoot(environment)
            .onChange(of: sharedQuestionListStore.acceptedShares.map(\.id)) { _, acceptedShareIDs in
                Self.storage.set(acceptedShareIDs, forKey: Self.acceptedShareIDsKey)
            }
    }

    @ViewBuilder
    private var screen: some View {
        if UITestLaunchOptions.isSharedQuestionListMainTabHarnessEnabled {
            MainTabView()
                .task { presentShareDeepLink() }
        } else if UITestLaunchOptions.isQuestionListDetailShareHarnessEnabled {
            NavigationStack {
                QuestionListsContentView()
            }
            .task {
                await refreshOwnedListSnapshotsForShareDetailHarness()
            }
        } else {
            HomeView()
                .task { presentShareDeepLink() }
        }
    }

    /// Stands in for the user opening a share link. The sheet it raises belongs to `appRoot(_:)`.
    private func presentShareDeepLink() {
        environment.deepLinkRouter.sharedQuestionList = SharedQuestionListDeepLink(
            shareCode: Self.shareCode
        )
    }

    private static var questionFixture: Question {
        Question(
            id: questionId,
            text: "Which conversation would you like to continue this week?",
            category: categoryId,
            localizedTexts: [
                "en": "Which conversation would you like to continue this week?"
            ]
        )
    }

    private static var shareFixture: QuestionListShare {
        let date = Date(timeIntervalSince1970: 100)
        return QuestionListShare(
            id: shareId,
            ownerId: "ui-test-owner",
            ownerDisplayName: "Fixture Owner",
            sourceListId: "ui-test-list",
            listName: "Shared Fixture",
            questionIds: [questionId],
            includeOwnerAnswers: false,
            ownerAnswerSnapshots: [:],
            shareCode: shareCode,
            recipientCap: QuestionListShare.defaultRecipientCap,
            acceptedRecipientCount: 0,
            status: .active,
            isLinkEnabled: true,
            createdAt: date,
            updatedAt: date
        )
    }

    private static var acceptedShareFixture: AcceptedQuestionListShare {
        let date = Date(timeIntervalSince1970: 100)
        let recipient = QuestionListShareRecipient(
            id: recipientUserId,
            shareId: shareId,
            recipientId: recipientUserId,
            recipientDisplayName: "TTB user",
            status: .accepted,
            latestReplyAnswerSnapshots: [:],
            repliedAt: nil,
            unreadByOwner: false,
            acceptedAt: date,
            updatedAt: date
        )
        return AcceptedQuestionListShare(share: shareFixture, recipient: recipient)
    }

    private static var compareShareFixture: QuestionListShare {
        let date = Date(timeIntervalSince1970: 300)
        return QuestionListShare(
            id: compareShareId,
            ownerId: recipientUserId,
            ownerDisplayName: "Fixture Owner",
            sourceListId: "ui-test-compare-list",
            listName: "Compare Fixture",
            questionIds: [questionId],
            includeOwnerAnswers: true,
            ownerAnswerSnapshots: [
                questionId: ["Continue the launch plan", "Ask about blockers", "Book time"]
            ],
            shareCode: compareShareCode,
            recipientCap: QuestionListShare.defaultRecipientCap,
            acceptedRecipientCount: 1,
            status: .active,
            isLinkEnabled: true,
            createdAt: date,
            updatedAt: date
        )
    }

    private static var compareRecipientFixture: QuestionListShareRecipient {
        let date = Date(timeIntervalSince1970: 320)
        return QuestionListShareRecipient(
            id: compareRecipientId,
            shareId: compareShareId,
            recipientId: compareRecipientId,
            recipientDisplayName: "Compare Friend",
            status: .accepted,
            latestReplyAnswerSnapshots: [
                questionId: ["Follow up tomorrow", "Send notes", "Keep it casual"]
            ],
            repliedAt: date,
            unreadByOwner: false,
            acceptedAt: date,
            updatedAt: date
        )
    }

    private static var listFixture: QuestionList {
        let date = Date(timeIntervalSince1970: 200)
        return QuestionList(
            id: listId,
            ownerId: recipientUserId,
            name: "Owned Fixture",
            questionIds: [questionId],
            visibility: "private",
            createdAt: date,
            updatedAt: date
        )
    }

    @MainActor
    private func refreshOwnedListSnapshotsForShareDetailHarness() async {
        for refreshIndex in 1...10 {
            try? await Task.sleep(nanoseconds: 700_000_000)
            var refreshedList = Self.listFixture
            refreshedList.updatedAt = Date(timeIntervalSince1970: 200 + Double(refreshIndex))
            environment.questionListStore.applyListenerSnapshotForTesting([refreshedList])
        }
    }
}
#endif
