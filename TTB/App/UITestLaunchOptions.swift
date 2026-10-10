import Foundation

enum UITestLaunchOptions {
    /// One case per harness the process can be launched into. Adding a harness means adding one
    /// case here with its `needsFirebase` flag — `allHarnessArguments` and
    /// `shouldSkipFirebaseConfiguration` are derived from this and cannot drift out of step with
    /// it the way three hand-maintained lists could.
    enum Harness: String, CaseIterable {
        case categoryQuestions = "-ui-test-category-questions-harness"
        /// Same fixture as the category-questions harness, but signed in anonymously so the
        /// guest favorite path (and its milestone toast) is the one exercised.
        case guestFavoriteMilestone = "-ui-test-guest-favorite-milestone-harness"
        case home = "-ui-test-home-harness"
        case homeProfileQuestionList = "-ui-test-home-profile-question-list-harness"
        case mostAnswered = "-ui-test-most-answered-harness"
        case ai = "-ui-test-ai-harness"
        case sharedQuestion = "-ui-test-shared-question-harness"
        case sharedQuestionList = "-ui-test-shared-question-list-harness"
        case sharedQuestionListMainTab = "-ui-test-shared-question-list-main-tab-harness"
        case questionListDetailShare = "-ui-test-question-list-detail-share-harness"
        case profile = "-ui-test-profile-harness"
        case profileAnonymous = "-ui-test-profile-anonymous-harness"

        /// Whether this harness needs Firebase configured. Every harness runs on local fixtures
        /// and skips it, except the guest-favorite milestone one, which signs in anonymously.
        var needsFirebase: Bool {
            self == .guestFavoriteMilestone
        }

        var isEnabled: Bool {
            ProcessInfo.processInfo.arguments.contains(rawValue)
        }
    }

    // Modifiers refine a harness rather than select one — no test launches with one alone — so
    // they are not `Harness` cases, matching the original list's exclusion of them.
    static let resetSharedQuestionListHarnessArgument = "-ui-test-reset-shared-question-list-harness"
    static let aiAnonymousHarnessArgument = "-ui-test-ai-anonymous"
    static let aiAtDailyLimitHarnessArgument = "-ui-test-ai-at-daily-limit"
    static let aiSeedDraftHarnessArgument = "-ui-test-ai-seed-draft"
    static let guestFavoritesOneBelowCapArgument = "-ui-test-guest-favorites-one-below-cap"
    static let homeSavedAnswerArgument = "-ui-test-home-saved-answer"

    static var isCategoryQuestionsHarnessEnabled: Bool { Harness.categoryQuestions.isEnabled }
    static var isGuestFavoriteMilestoneHarnessEnabled: Bool { Harness.guestFavoriteMilestone.isEnabled }
    static var isHomeHarnessEnabled: Bool { Harness.home.isEnabled }
    static var isHomeProfileQuestionListHarnessEnabled: Bool { Harness.homeProfileQuestionList.isEnabled }
    static var isMostAnsweredHarnessEnabled: Bool { Harness.mostAnswered.isEnabled }
    static var isAIHarnessEnabled: Bool { Harness.ai.isEnabled }
    static var isSharedQuestionHarnessEnabled: Bool { Harness.sharedQuestion.isEnabled }
    static var isSharedQuestionListHarnessEnabled: Bool { Harness.sharedQuestionList.isEnabled }

    static var isSharedQuestionListMainTabHarnessEnabled: Bool {
        Harness.sharedQuestionListMainTab.isEnabled
    }

    static var shouldResetSharedQuestionListHarness: Bool {
        ProcessInfo.processInfo.arguments.contains(resetSharedQuestionListHarnessArgument)
    }

    static var isQuestionListDetailShareHarnessEnabled: Bool { Harness.questionListDetailShare.isEnabled }
    static var isProfileHarnessEnabled: Bool { Harness.profile.isEnabled }
    static var isProfileAnonymousHarnessEnabled: Bool { Harness.profileAnonymous.isEnabled }

    static var isAIAnonymousHarnessEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains(aiAnonymousHarnessArgument)
    }

    static var isAIAtDailyLimitHarnessEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains(aiAtDailyLimitHarnessArgument)
    }

    static var isAISeedDraftHarnessEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains(aiSeedDraftHarnessArgument)
    }

    /// The guest favorite cap is ten and the category fixture holds three questions, so a UI test
    /// cannot tap its way to the cap. This asks the harness to start one favorite below it.
    static var shouldSeedGuestFavoritesOneBelowCap: Bool {
        ProcessInfo.processInfo.arguments.contains(guestFavoritesOneBelowCapArgument)
    }

    /// Starts the home harness with a saved answer on its first question, so a test can tell a
    /// dropped draft from a saved one.
    static var shouldSeedHomeSavedAnswer: Bool {
        ProcessInfo.processInfo.arguments.contains(homeSavedAnswerArgument)
    }

    /// Every argument that means "this launch is a harness".
    static var allHarnessArguments: [String] {
        Harness.allCases.map(\.rawValue)
    }

    static func isAnyHarness(in arguments: [String]) -> Bool {
        arguments.contains { allHarnessArguments.contains($0) }
    }

    static var isAnyHarnessEnabled: Bool {
        isAnyHarness(in: ProcessInfo.processInfo.arguments)
    }

    static var shouldSkipFirebaseConfiguration: Bool {
        #if DEBUG
        Harness.allCases.contains { !$0.needsFirebase && $0.isEnabled }
        #else
        false
        #endif
    }
}
