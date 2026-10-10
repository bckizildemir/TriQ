import SwiftUI

#if DEBUG
/// The Home screen on fixture categories, optionally with the profile route the sheet tests drive.
struct UITestHomeRootView: View {
    private static let profileUserId = "ui-test-home-profile-user"
    private static let profileListId = "ui-test-home-profile-list"
    private static let profileQuestionId = "ui-test-home-profile-question"

    @StateObject private var environment: AppEnvironment
    @State private var churnCounter = 0

    init() {
        let isProfileHarness = UITestLaunchOptions.isHomeProfileQuestionListHarnessEnabled

        _environment = StateObject(
            wrappedValue: .uiTest(
                storage: .harnessSuite(named: "UITestHomeRootView"),
                authModel: UITestAuthModelFactory.permanentUser(uid: Self.profileUserId),
                questionModel: QuestionModel(
                    localQuestions: isProfileHarness
                        ? UITestHomeFixture.questions + [Self.profileQuestionFixture]
                        : UITestHomeFixture.questions,
                    localUserAnswers: UITestLaunchOptions.shouldSeedHomeSavedAnswer
                        ? UITestHomeFixture.savedAnswers(userId: Self.profileUserId)
                        : [:]
                ),
                profileModel: isProfileHarness
                    ? ProfileModel(
                        uiTestUsername: "Home Profile Harness",
                        email: "home-profile@example.com",
                        statistics: .init(daily: 3, weekly: 9, total: 27)
                    )
                    : nil,
                categoryModel: CategoryModel(localCategories: UITestHomeFixture.categories),
                questionListStore: QuestionListStore(
                    localLists: isProfileHarness ? [Self.profileListFixture] : []
                ),
                // This harness churns the list every 250 ms, so a dismiss tap can land while the
                // sheet is still presenting. `SimulatorSafeSheetDismissButton` used to read the
                // launch argument itself; the harness that needs the delay states it instead.
                sheetDismissDelay: isProfileHarness ? .milliseconds(700) : .zero
            )
        )
    }

    var body: some View {
        HomeView(
            profileViewBuilder: UITestLaunchOptions.isHomeProfileQuestionListHarnessEnabled
                ? { ProfileView(model: environment.profileModel) }
                : nil
        )
        .overlay {
            Text("home-profile-harness-\(churnCounter)")
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        }
        .appRoot(environment)
        .task {
            await runProfileHarnessChurnLoopIfNeeded()
        }
    }

    @MainActor
    private func runProfileHarnessChurnLoopIfNeeded() async {
        guard UITestLaunchOptions.isHomeProfileQuestionListHarnessEnabled else { return }

        for index in 1...80 {
            try? await Task.sleep(nanoseconds: 250_000_000)
            churnCounter = index

            var list = Self.profileListFixture
            list.updatedAt = Date(timeIntervalSince1970: 300 + Double(index))
            environment.questionListStore.applyListenerSnapshotForTesting([list])
        }
    }

    private static var profileQuestionFixture: Question {
        Question(
            id: profileQuestionId,
            text: "What are 3 conversation topics you dislike?",
            category: UITestHomeFixture.categoryID,
            localizedTexts: [
                "en": "What are 3 conversation topics you dislike?"
            ]
        )
    }

    private static var profileListFixture: QuestionList {
        let date = Date(timeIntervalSince1970: 300)
        return QuestionList(
            id: profileListId,
            ownerId: profileUserId,
            name: "Home Profile Fixture",
            questionIds: [profileQuestionId],
            visibility: "private",
            createdAt: date,
            updatedAt: date
        )
    }
}
#endif
