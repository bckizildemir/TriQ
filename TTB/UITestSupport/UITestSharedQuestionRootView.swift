import SwiftUI

#if DEBUG
/// The shared-question deep link, presented over Home as it is in production.
///
/// It used to render `AppEnvironmentRootView` with a plain `AuthModel`, which reports signed out
/// without Firebase, so the sheet actually presented over the *login* screen. Fixture auth plus
/// `appRoot(_:)` gets a signed-in screen with the deep-link sheet over it.
///
/// Home rather than `MainTabView`, deliberately: this harness does not need the tab bar to present
/// a sheet, and Home is the smaller surface.
struct UITestSharedQuestionRootView: View {
    @StateObject private var environment: AppEnvironment

    init() {
        _environment = StateObject(
            wrappedValue: .uiTest(
                storage: .harnessSuite(named: "UITestSharedQuestionRootView"),
                authModel: UITestAuthModelFactory.permanentUser(uid: "ui-test-shared-question-user"),
                questionModel: QuestionModel(localQuestions: [Self.sharedQuestion]),
                initialDeepLinkURL: Self.sharedQuestionURL
            )
        )
    }

    var body: some View {
        HomeView()
            .appRoot(environment)
    }

    private static let sharedQuestion = Question(
        id: "ui-test-shared-question-1",
        text: "Which three memories would you want to share with a close friend?",
        category: "Friendship",
        createdBy: "ui-test-user",
        creatorUsername: "tester"
    )

    private static let sharedQuestionURL = URL(
        string: "https://ttbp-9d652.web.app/q/\(sharedQuestion.id)"
    )!
}
#endif
