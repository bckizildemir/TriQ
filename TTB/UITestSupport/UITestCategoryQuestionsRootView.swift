import SwiftUI

#if DEBUG
/// One category screen on fixture questions, signed in as a guest or as an account.
///
/// The guest-favorite milestone variant runs anonymously so the guest favorite path is the one
/// exercised. Both the guest-upgrade sheet and the favorite-limit sheet now arrive with
/// `appRoot(_:)` — this harness used to hand-copy the first and could not reach the second at all.
struct UITestCategoryQuestionsRootView: View {
    @StateObject private var environment: AppEnvironment

    init() {
        let isGuest = UITestLaunchOptions.isGuestFavoriteMilestoneHarnessEnabled

        _environment = StateObject(
            wrappedValue: .uiTest(
                storage: .harnessSuite(named: "UITestCategoryQuestionsRootView"),
                authModel: isGuest
                    ? UITestAuthModelFactory.anonymousUser()
                    : UITestAuthModelFactory.permanentUser(uid: "ui-test-category-questions-user"),
                questionModel: QuestionModel(
                    localQuestions: UITestCategoryQuestionsFixture.questions,
                    localUserAnswers: UITestCategoryQuestionsFixture.userAnswers
                )
            )
        )
    }

    var body: some View {
        NavigationStack {
            CategoryQuestionsView(
                category: UITestCategoryQuestionsFixture.categoryID,
                model: environment.questionModel,
                badgeModel: nil
            )
        }
        .appRoot(environment)
    }
}
#endif
