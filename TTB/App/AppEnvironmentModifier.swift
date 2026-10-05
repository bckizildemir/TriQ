import SwiftUI

/// Installs every model in an `AppEnvironment` as an environment object.
///
/// Applied in each presentation context, not just once: a sheet body is a new context, so the app
/// root and both deep-link sheets used to re-list nine `environmentObject` calls each, and
/// `UITestSharedQuestionListRootView` listed them twice more. This is that list, once.
struct AppEnvironmentModifier: ViewModifier {
    let environment: AppEnvironment

    func body(content: Content) -> some View {
        content
            .environment(\.aiService, environment.aiService)
            .environment(\.answerImageSuggestionService, environment.answerImageSuggestionService)
            .environment(\.answerDraftStore, environment.answerDraftStore)
            .environment(\.sheetDismissDelay, environment.sheetDismissDelay)
            .environmentObject(environment.authModel)
            .environmentObject(environment.questionModel)
            .environmentObject(environment.answerModel)
            .environmentObject(environment.favoriteStore)
            .environmentObject(environment.guestFavoriteModel)
            .environmentObject(environment.questionListStore)
            .environmentObject(environment.sharedQuestionListStore)
            .environmentObject(environment.profileModel)
            .environmentObject(environment.categoryModel)
            .environmentObject(environment.notificationService)
            .environmentObject(environment.deepLinkRouter)
            .environmentObject(environment.badgeModel)
    }
}

// MARK: - Service slots

extension EnvironmentValues {
    /// The AI backend a screen may use, or `nil` for the app's no-AI mode.
    ///
    /// The default is `nil` on purpose. A screen rendered outside `appEnvironment(_:)` gets no service
    /// rather than a live one, so a harness that forgets the modifier cannot reach the network — the
    /// direction `docs/adr/0005` argues for. Production installs the live service here.
    @Entry var aiService: (any AIServiceProtocol)? = nil
}

extension EnvironmentValues {
    /// The image-suggestion backend a screen may use, or `nil` for the app's no-suggestion mode.
    ///
    /// Same direction as `aiService`: absent by default, live only where the app installs it.
    @Entry var answerImageSuggestionService: AnswerImageSuggestionService? = nil
}

// MARK: - Sheet timing

extension EnvironmentValues {
    /// How long `SimulatorSafeSheetDismissButton` refuses its own tap after a sheet appears.
    ///
    /// Zero is the app's answer, and the only reason the value exists is that a UI test can tap a
    /// dismiss button before the simulator finishes presenting the sheet. One harness raises it.
    @Entry var sheetDismissDelay: Duration = .zero
}

extension View {
    /// Installs the app's models. Use this inside a sheet body; use `appRoot(_:)` for a root.
    func appEnvironment(_ environment: AppEnvironment) -> some View {
        modifier(AppEnvironmentModifier(environment: environment))
    }
}
