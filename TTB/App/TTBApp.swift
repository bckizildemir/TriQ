import SwiftUI
import FirebaseCore
import FirebaseAuth
import FirebaseMessaging
import Nuke
import os

class AppDelegate: NSObject, UIApplicationDelegate {
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.ttb.app",
        category: "AppDelegate")

    func application(_ application: UIApplication,
                    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        ImagePipeline.shared = ImagePipeline(configuration: .withDataCache)

        // A unit-test host is a container for the test bundle, not an app launch (#112): it must not
        // attest, register for remote notifications, or open the live environment's listeners. Only
        // Firebase itself is still configured — it connects to nothing until a request is made, and
        // a suite that reads the shared `NotificationService` reaches `Auth.auth()`, which traps
        // when the default app is missing.
        if UnitTestHost.isHostingUnitTests {
            if FirebaseApp.app() == nil {
                FirebaseApp.configure()
            }
            return true
        }

        // Before every FirebaseApp.configure() below, including the harness one: Firebase reads the
        // App Check factory while it configures.
        AppCheckInstaller.install(AppCheckPolicy.provider(for: .current))

        if UITestLaunchOptions.shouldSkipFirebaseConfiguration {
            if FirebaseApp.app() == nil {
                FirebaseApp.configure()
            }
            return true
        }

        FirebaseApp.configure()

        logger.info("Firebase configured for project \(FirebaseApp.app()?.options.projectID ?? "N/A")")
        NotificationService.shared.configure(application: application)

        if let remoteNotification = launchOptions?[.remoteNotification] as? [AnyHashable: Any] {
            NotificationService.shared.handleRemoteNotification(remoteNotification)
        }
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        NotificationService.shared.handleAPNSToken(deviceToken)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        logger.error("Failed to register for remote notifications: \(error.localizedDescription)")
    }
}

@main
struct TTBApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        WindowGroup {
            rootView
        }
    }

    @ViewBuilder
    private var rootView: some View {
        #if DEBUG
        if UnitTestHost.isHostingUnitTests {
            // Nothing to render: this launch exists only to hold the test bundle (#112). The live
            // `AppEnvironment` is built on first render, so skipping it here is what keeps a
            // unit-test run off the live project — its listeners are the ones that showed up as an
            // App Check failure in a test log.
            Color.clear
        } else if UITestLaunchOptions.isCategoryQuestionsHarnessEnabled
            || UITestLaunchOptions.isGuestFavoriteMilestoneHarnessEnabled {
            UITestCategoryQuestionsRootView()
        } else if UITestLaunchOptions.isHomeHarnessEnabled
            || UITestLaunchOptions.isHomeProfileQuestionListHarnessEnabled {
            UITestHomeRootView()
        } else if UITestLaunchOptions.isMostAnsweredHarnessEnabled {
            UITestMostAnsweredRootView()
        } else if UITestLaunchOptions.isAIHarnessEnabled {
            UITestAIRootView()
        } else if UITestLaunchOptions.isSharedQuestionHarnessEnabled {
            UITestSharedQuestionRootView()
        } else if UITestLaunchOptions.isSharedQuestionListMainTabHarnessEnabled {
            UITestSharedQuestionListRootView()
        } else if UITestLaunchOptions.isSharedQuestionListHarnessEnabled {
            UITestSharedQuestionListRootView()
        } else if UITestLaunchOptions.isQuestionListDetailShareHarnessEnabled {
            UITestSharedQuestionListRootView()
        } else if UITestLaunchOptions.isProfileHarnessEnabled
            || UITestLaunchOptions.isProfileAnonymousHarnessEnabled {
            UITestProfileRootView()
        } else {
            AppEnvironmentRootView()
        }
        #else
        AppEnvironmentRootView()
        #endif
    }
}
