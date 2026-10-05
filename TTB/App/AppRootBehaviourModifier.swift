import SwiftUI
import UIKit

/// The cross-screen behaviour a screen gets from being inside the app, as one modifier.
///
/// This is the other half of AD-3. Three of these lived only in `AppEnvironmentRootView.body`, so a
/// UI-test harness — which renders one screen rather than the app root — could not reach them at
/// all: the favorite-limit sheet, guest-favorite migration, and foreground notification
/// re-registration. Six harnesses hand-copied the parts they did need, and the guest-upgrade sheet
/// was copied rather than shared. Now the app root and every harness apply the same modifier, so a
/// divergence has nowhere to hide.
///
/// Harnesses apply this to their own screen, never to `AppRootView`. `AuthenticatedRootView` builds
/// its `OnboardingViewModel` with no seam and `OnboardingStateStore` reads Firestore, so a harness
/// that rendered the real root would land on the onboarding flow. See `docs/adr/0008`.
///
/// Only four models are observed, where the old root observed all eleven — the rest are read when a
/// sheet body is built, which is the only place they are needed.
struct AppRootBehaviourModifier: ViewModifier {
    let environment: AppEnvironment

    @ObservedObject private var authModel: AuthModel
    @ObservedObject private var guestFavoriteModel: GuestFavoriteModel
    @ObservedObject private var deepLinkRouter: AppDeepLinkRouter
    @ObservedObject private var toastCenter: ToastCenter

    @State private var isMigratingGuestFavorites = false
    /// The Upgrade Prompt and the upgrade sheet it opens present from the topmost controller, not
    /// from a `.sheet` here, so they still appear over a `fullScreenCover`. See `docs/adr/0010`.
    @State private var upgradePromptPresenter = TopmostSheetPresenter(presenter: WindowTopmostPresenter())
    @State private var guestUpgradePresenter = TopmostSheetPresenter(presenter: WindowTopmostPresenter())

    init(environment: AppEnvironment) {
        self.environment = environment
        _authModel = ObservedObject(wrappedValue: environment.authModel)
        _guestFavoriteModel = ObservedObject(wrappedValue: environment.guestFavoriteModel)
        _deepLinkRouter = ObservedObject(wrappedValue: environment.deepLinkRouter)
        _toastCenter = ObservedObject(wrappedValue: environment.toastCenter)
    }

    func body(content: Content) -> some View {
        lifecycleBehavior(on: presentationSheets(on: content.appEnvironment(environment)))
    }

    /// The four sheets this modifier owns: the Upgrade Prompt, the guest-upgrade sheet, and the two
    /// deep-link sheets. The first two present from the topmost controller, because a guest can
    /// reach the favorite cap from inside a `fullScreenCover`.
    @ViewBuilder
    private func presentationSheets<Content: View>(on content: Content) -> some View {
        content
            .onChange(of: toastCenter.isGuestFavoriteLimitPromptPresented, initial: true) { _, isPresented in
                upgradePromptPresenter.update(
                    isPresented: isPresented,
                    makeController: makeUpgradePromptController,
                    onDismissedBySystem: dismissFavoriteLimit
                )
            }
            .onChange(of: guestFavoriteModel.shouldShowGuestUpgrade, initial: true) { _, isPresented in
                guestUpgradePresenter.update(
                    isPresented: isPresented,
                    makeController: makeGuestUpgradeController,
                    onDismissedBySystem: dismissGuestUpgrade
                )
            }
            .sheet(item: $deepLinkRouter.sharedQuestion) { deepLink in
                SharedQuestionSheetView(questionId: deepLink.questionId)
                    .appEnvironment(environment)
            }
            .sheet(item: $deepLinkRouter.sharedQuestionList) { deepLink in
                SharedQuestionListSheetView(shareCode: deepLink.shareCode)
                    .appEnvironment(environment)
            }
    }

    /// The toast host, deep-link handling, and the background tasks that keep favorites, migration,
    /// and notification registration in sync with auth state.
    @ViewBuilder
    private func lifecycleBehavior<Content: View>(on content: Content) -> some View {
        content
            .appToastHost(toastCenter)
            .guestFavoriteMilestoneToast(
                guestFavoriteModel: guestFavoriteModel,
                toastCenter: toastCenter
            )
            .onOpenURL(perform: deepLinkRouter.handle)
            .onContinueUserActivity(NSUserActivityTypeBrowsingWeb, perform: handleUserActivity)
            .task(id: environment.favoriteIdentity) {
                await environment.favoriteStore.setIdentity(environment.favoriteIdentity)
            }
            .task(id: guestFavoriteMigrationTaskID) {
                await migrateGuestFavoritesIfNeeded()
            }
            .task(id: environment.initialDeepLinkURL) {
                guard let initialDeepLinkURL = environment.initialDeepLinkURL else { return }
                deepLinkRouter.handle(initialDeepLinkURL)
            }
            .onChange(of: guestFavoriteModel.migrationSuccessMessage) { _, message in
                showMigrationSuccess(message)
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                Task {
                    await refreshNotificationRegistration()
                }
            }
    }

    private var guestFavoriteMigrationTaskID: String {
        [
            authModel.currentUserId ?? "none",
            authModel.isAuthenticated ? "authenticated" : "signedOut",
            authModel.isAnonymous ? "anonymous" : "permanent",
            String(guestFavoriteModel.getFavoriteCount())
        ].joined(separator: ":")
    }

    private func makeUpgradePromptController() -> UIViewController {
        hosted(
            FavoriteLimitSheet(
                savedQuestions: environment.guestFavoritePreviewQuestions,
                onCreateAccount: createAccountFromFavoriteLimit,
                onMaybeLater: dismissFavoriteLimit
            )
        )
    }

    private func makeGuestUpgradeController() -> UIViewController {
        hosted(GuestUpgradeView())
    }

    /// A UIKit-hosted sheet is a new presentation context, so it gets the app's models again.
    private func hosted<Sheet: View>(_ sheet: Sheet) -> UIViewController {
        UIHostingController(
            rootView: sheet
                .appEnvironment(environment)
                .environment(\.toastCenter, toastCenter)
        )
    }

    /// The upgrade sheet is raised only once the prompt is off screen: UIKit refuses to present
    /// from a controller that is still being dismissed.
    private func createAccountFromFavoriteLimit() {
        upgradePromptPresenter.dismiss {
            toastCenter.isGuestFavoriteLimitPromptPresented = false
            guestFavoriteModel.requestGuestUpgrade()
        }
    }

    private func dismissFavoriteLimit() {
        toastCenter.isGuestFavoriteLimitPromptPresented = false
    }

    private func dismissGuestUpgrade() {
        guestFavoriteModel.shouldShowGuestUpgrade = false
    }

    private func handleUserActivity(_ userActivity: NSUserActivity) {
        guard let url = userActivity.webpageURL else { return }
        deepLinkRouter.handle(url)
    }

    /// Its own identifier, not the shared `app-toast`: this is the only signal a test has that
    /// guest favorites actually migrated onto the account.
    private func showMigrationSuccess(_ message: String?) {
        guard let message else { return }
        toastCenter.showSuccess(
            title: message,
            accessibilityIdentifier: "guest-favorite-migration-toast"
        )
        guestFavoriteModel.clearMigrationSuccessMessage()
    }

    private func migrateGuestFavoritesIfNeeded() async {
        guard !isMigratingGuestFavorites else { return }
        guard authModel.isAuthenticated, !authModel.isAnonymous else { return }
        guard let userId = authModel.currentUserId, !userId.isEmpty else { return }
        guard guestFavoriteModel.getFavoriteCount() > 0 else { return }

        isMigratingGuestFavorites = true
        defer { isMigratingGuestFavorites = false }

        // The store keeps the local ids when the write fails, so the next permanent-authenticated
        // app state retries; the write itself is idempotent.
        await environment.favoriteStore.migrateGuestFavorites(to: userId)
    }

    private func refreshNotificationRegistration() async {
        await environment.notificationService.refreshAuthorizationStatus()
        await environment.notificationService.syncCurrentDeviceRegistration()
    }
}

extension View {
    /// Installs the app's models *and* its cross-screen behaviour. Every root — the app's own and
    /// every UI-test harness — applies this, which is what keeps the two from drifting.
    func appRoot(_ environment: AppEnvironment) -> some View {
        modifier(AppRootBehaviourModifier(environment: environment))
    }
}
