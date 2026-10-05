import SwiftUI

#if DEBUG
/// The Best-Of screen on preloaded ranking fixtures.
struct UITestMostAnsweredRootView: View {
    @StateObject private var environment: AppEnvironment

    private let viewModel: MostAnsweredViewModel

    init() {
        let dailyItems = Self.preloadedDailyItems
        let allTimeItems = Self.preloadedAllTimeItems

        _environment = StateObject(
            wrappedValue: .uiTest(
                storage: .harnessSuite(named: "UITestMostAnsweredRootView"),
                authModel: UITestAuthModelFactory.permanentUser(uid: "ui-test-most-answered-user"),
                questionModel: QuestionModel(
                    localQuestions: (dailyItems + allTimeItems).map(\.question)
                )
            )
        )
        viewModel = MostAnsweredViewModel(
            preloadedDailyItems: dailyItems,
            preloadedAllTimeItems: allTimeItems
        )
    }

    var body: some View {
        MostAnsweredView(viewModel: viewModel)
            .appRoot(environment)
    }

    private static let preloadedDailyItems = [
        MostAnsweredItem(
            question: Question(
                id: "preview-most-answered-1",
                text: "Today, which three moments felt the most meaningful?",
                category: "Daily",
                totalRespondents: 24,
                answerStats: [
                    "0": ["Morning walk": 6],
                    "1": ["Focused work": 5],
                    "2": ["Dinner with friends": 4]
                ]
            ),
            userAnswers: ["Morning walk", "Focused work", "Dinner with friends"]
        ),
        MostAnsweredItem(
            question: Question(
                id: "preview-most-answered-2",
                text: "What are the three habits you want to keep this month?",
                category: "Goals",
                totalRespondents: 18,
                answerStats: [
                    "0": ["Reading": 7],
                    "1": ["Training": 6],
                    "2": ["Planning": 4]
                ]
            ),
            userAnswers: ["Reading", "Training", "Planning"]
        )
    ]

    private static let preloadedAllTimeItems = [
        MostAnsweredItem(
            question: Question(
                id: "preview-most-answered-3",
                text: "Which three career milestones matter most to you?",
                category: "Career",
                totalRespondents: 31,
                answerStats: [
                    "0": ["Launching a product": 9],
                    "1": ["Leading a team": 8],
                    "2": ["Teaching others": 6]
                ]
            ),
            userAnswers: ["Launching a product", "Leading a team", "Teaching others"]
        ),
        MostAnsweredItem(
            question: Question(
                id: "preview-most-answered-4",
                text: "What are the three routines that keep you healthy?",
                category: "Health",
                totalRespondents: 27,
                answerStats: [
                    "0": ["Walking": 10],
                    "1": ["Stretching": 7],
                    "2": ["Good sleep": 8]
                ]
            ),
            userAnswers: ["Walking", "Stretching", "Good sleep"]
        )
    ]
}
#endif
