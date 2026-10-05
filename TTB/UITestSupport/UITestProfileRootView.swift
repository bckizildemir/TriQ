import SwiftUI

#if DEBUG
/// The profile screen with an owned question list, as a permanent account or as a guest.
///
/// The churn loop is the point of the harness rather than decoration: `ProfileView` is reached
/// through a `navigationDestination`, so it re-evaluates on every parent update, and a sheet that
/// cannot survive that is the bug these tests catch.
struct UITestProfileRootView: View {
    private static let userId = "ui-test-profile-user"
    private static let listId = "ui-test-profile-list"
    private static let questionId = "ui-test-profile-question"

    @StateObject private var environment: AppEnvironment
    @State private var churnCounter = 0

    init() {
        _environment = StateObject(
            wrappedValue: .uiTest(
                storage: .harnessSuite(named: "UITestProfileRootView"),
                authModel: UITestLaunchOptions.isProfileAnonymousHarnessEnabled
                    ? UITestAuthModelFactory.anonymousUser()
                    : UITestAuthModelFactory.permanentUser(uid: Self.userId),
                questionModel: QuestionModel(localQuestions: [Self.questionFixture]),
                profileModel: ProfileModel(
                    uiTestUsername: "Profile Harness",
                    email: "profile@example.com",
                    statistics: .init(daily: 3, weekly: 9, total: 27)
                ),
                questionListStore: QuestionListStore(localLists: [Self.listFixture])
            )
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            Text("profile-harness-\(churnCounter)")
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)

            ProfileView(model: environment.profileModel)
        }
        .appRoot(environment)
        .task {
            await runChurnLoop()
        }
    }

    @MainActor
    private func runChurnLoop() async {
        for index in 1...80 {
            try? await Task.sleep(nanoseconds: 250_000_000)
            churnCounter = index
        }
    }

    private static var questionFixture: Question {
        Question(
            id: questionId,
            text: "What are 3 conversation topics you dislike?",
            category: "Career",
            localizedTexts: [
                "en": "What are 3 conversation topics you dislike?"
            ]
        )
    }

    private static var listFixture: QuestionList {
        let date = Date(timeIntervalSince1970: 300)
        return QuestionList(
            id: listId,
            ownerId: userId,
            name: "Owned Fixture",
            questionIds: [questionId],
            visibility: "private",
            createdAt: date,
            updatedAt: date
        )
    }
}
#endif
