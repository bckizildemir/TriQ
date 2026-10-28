import SwiftUI

#if DEBUG
/// The Trio composer on a mock AI service, as a guest or as an account.
///
/// The anonymous case used to travel through `\.uitestAuthIsAnonymous`, a second source of truth
/// for anonymity that `AIView` read in production code. Fixture auth reports it honestly instead,
/// so that environment key is gone.
struct UITestAIRootView: View {
    @StateObject private var environment: AppEnvironment
    @StateObject private var trioModel: TrioPromptModel

    init() {
        let isAnonymous = UITestLaunchOptions.isAIAnonymousHarnessEnabled

        let questionModel = QuestionModel(localQuestions: [])
        if UITestLaunchOptions.shouldUseAILongFeed {
            questionModel.replaceTrioQuestionsForTesting(Self.longFeed, selectedLanguageCode: "en")
        }

        _environment = StateObject(
            wrappedValue: .uiTest(
                storage: .harnessSuite(named: "UITestAIRootView"),
                authModel: isAnonymous
                    ? UITestAuthModelFactory.anonymousUser()
                    : UITestAuthModelFactory.permanentUser(uid: "ui-test-ai-user"),
                questionModel: questionModel
            )
        )

        if UITestLaunchOptions.isAIAtDailyLimitHarnessEnabled {
            _trioModel = StateObject(
                wrappedValue: UITestTrioModelFactory.makeTrioModelAtDailyLimit(
                    isAnonymous: isAnonymous
                )
            )
        } else {
            _trioModel = StateObject(wrappedValue: UITestTrioModelFactory.makeTrioModel())
        }
    }

    var body: some View {
        AIView(trioModel: trioModel)
            .appRoot(environment)
            .onAppear(perform: seedDraftIfNeeded)
    }

    /// Six English Trio questions: more than one iPhone 12 screen of cards.
    private static let longFeed = (1...6).map { index in
        Question(
            id: "ui-test-trio-\(index)",
            text: "Which three things made day \(index) feel worth remembering?",
            category: "Daily",
            languageCode: "en"
        )
    }

    private func seedDraftIfNeeded() {
        guard UITestLaunchOptions.isAISeedDraftHarnessEnabled else { return }
        trioModel.selectVariation("What are the top 3 parts of this topic?")
    }
}
#endif
