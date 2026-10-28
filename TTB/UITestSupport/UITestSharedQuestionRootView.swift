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
                initialDeepLinkURL: Self.deepLinkURL
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

    /// With `-ui-test-shared-question-unknown` the link names a question the model does not hold,
    /// which is the not-found state.
    private static var deepLinkURL: URL {
        let isUnknown = ProcessInfo.processInfo.arguments.contains("-ui-test-shared-question-unknown")
        let questionId = isUnknown ? "ui-test-unknown-question" : sharedQuestion.id
        return URL(string: "https://ttbp-9d652.web.app/q/\(questionId)")!
    }
}
#endif
