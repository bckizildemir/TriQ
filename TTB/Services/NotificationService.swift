import FirebaseAuth
import FirebaseFirestore
import FirebaseMessaging
import Foundation
import os
import SwiftUI
import UIKit
import UserNotifications

@MainActor
final class NotificationService: NSObject, ObservableObject {
    static let shared = NotificationService()

    @Published private(set) var authorizationStatus: NotificationAuthorizationState = .notDetermined
    @Published private(set) var contentUpdatesEnabled = false
    @Published private(set) var isSyncing = false
    @Published var presentedReleaseID: String?

    private let db = Firestore.firestore()
    private let notificationCenter = UNUserNotificationCenter.current()
    private var authListener: AuthStateDidChangeListenerHandle?
    private var deviceListener: ListenerRegistration?
    private var fcmToken: String?
    private var hasAPNSToken = false
    private var lastKnownUserID: String?
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.ttb.app",
        category: "Notifications")

    private override init() {
        super.init()
        notificationCenter.delegate = self
        authListener = Auth.auth().addStateDidChangeListener { [weak self] _, _ in
            Task { @MainActor in
                await self?.handleAuthStateChanged()
            }
        }
        Task {
            await refreshAuthorizationStatus()
        }
    }

    /// `isolated` so the cleanup can read the main-actor listener handles. Below iOS 18.4 the
    /// compiler links a main-actor back-deploy shim, so this needs no deployment-target change.
    isolated deinit {
        if let authListener {
            Auth.auth().removeStateDidChangeListener(authListener)
        }
        deviceListener?.remove()
    }

    func configure(application: UIApplication) {
        Messaging.messaging().delegate = self
        application.registerForRemoteNotifications()
        Task {
            await refreshAuthorizationStatus()
            await syncCurrentDeviceRegistration()
        }
    }

    @discardableResult
    func requestAuthorization() async throws -> Bool {
        let granted = try await notificationCenter.requestAuthorization(options: [.alert, .badge, .sound])
        await refreshAuthorizationStatus()

        if granted {
            UIApplication.shared.registerForRemoteNotifications()
            contentUpdatesEnabled = true
            await syncCurrentDeviceRegistration()
        }

        return granted
    }

    func refreshAuthorizationStatus() async {
        let settings = await notificationCenter.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            authorizationStatus = .authorized
        case .denied:
            authorizationStatus = .denied
        case .notDetermined:
            authorizationStatus = .notDetermined
        @unknown default:
            authorizationStatus = .notDetermined
        }
    }

    func updateContentUpdatesEnabled(_ isEnabled: Bool) async {
        contentUpdatesEnabled = isEnabled
        await syncCurrentDeviceRegistration()
    }

    func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    func handleAPNSToken(_ deviceToken: Data) {
        hasAPNSToken = true
        Messaging.messaging().apnsToken = deviceToken
        Task {
            await syncCurrentDeviceRegistration()
        }
    }

    func handleRemoteNotification(_ userInfo: [AnyHashable: Any]) {
        presentRelease(id: Self.releaseID(from: userInfo))
    }

    private func presentRelease(id releaseID: String?) {
        if let releaseID {
            presentedReleaseID = releaseID
        }
    }

    nonisolated static func releaseID(from userInfo: [AnyHashable: Any]) -> String? {
        userInfo["releaseId"] as? String
    }

    private func handleAuthStateChanged() async {
        let currentUserID = Auth.auth().currentUser?.uid

        if let lastKnownUserID, lastKnownUserID != currentUserID {
            try? await deviceDocumentReference(userId: lastKnownUserID).delete()
        }

        deviceListener?.remove()
        deviceListener = nil
        await refreshAuthorizationStatus()

        guard let userId = currentUserID else {
            lastKnownUserID = nil
            contentUpdatesEnabled = false
            return
        }

        lastKnownUserID = userId

        let deviceRef = deviceDocumentReference(userId: userId)
        deviceListener = deviceRef.addSnapshotListener { [weak self] snapshot, _ in
            guard let data = snapshot?.data() else { return }
            let device = NotificationDevice.fromFirestore(data, id: snapshot?.documentID ?? "")
            Task { @MainActor in
                self?.contentUpdatesEnabled = device.contentUpdatesEnabled
            }
        }

        if let existingData = try? await deviceRef.getDocument().data() {
            let existingDevice = NotificationDevice.fromFirestore(existingData, id: installationID)
            contentUpdatesEnabled = existingDevice.contentUpdatesEnabled
        } else {
            contentUpdatesEnabled = authorizationStatus == .authorized
        }

        await syncCurrentDeviceRegistration()
    }

    func syncCurrentDeviceRegistration() async {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        guard hasAPNSToken else { return }
        let authorizationStatus = authorizationStatus
        var token = fcmToken
        if token == nil {
            token = try? await fetchFCMToken()
        }

        guard let token, !token.isEmpty else { return }

        fcmToken = token
        isSyncing = true
        defer { isSyncing = false }

        let effectiveContentUpdatesEnabled = contentUpdatesEnabled
        let device = NotificationDevice(
            id: installationID,
            fcmToken: token,
            localeCode: preferredLocaleCode,
            contentUpdatesEnabled: effectiveContentUpdatesEnabled,
            authorizationStatus: authorizationStatus,
            isPushEligible: authorizationStatus == .authorized && effectiveContentUpdatesEnabled,
            appVersion: appVersion
        )

        do {
            try await deviceDocumentReference(userId: userId).setData(device.toFirestore(), merge: true)
            contentUpdatesEnabled = effectiveContentUpdatesEnabled
        } catch {
            logger.error("Failed to sync notification device: \(error.localizedDescription)")
        }
    }

    private var installationID: String {
        KeychainManager.shared.installationIdentifier()
    }

    private var preferredLocaleCode: String {
        AppLocalization.currentLanguageCode
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
    }

    private func deviceDocumentReference(userId: String) -> DocumentReference {
        db.collection("users")
            .document(userId)
            .collection("notificationDevices")
            .document(installationID)
    }

    private func fetchFCMToken() async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            Messaging.messaging().token { token, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: token ?? "")
                }
            }
        }
    }
}

extension NotificationService: MessagingDelegate {
    nonisolated func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let fcmToken else { return }
        Task { @MainActor in
            self.fcmToken = fcmToken
            await self.syncCurrentDeviceRegistration()
        }
    }
}

extension NotificationService: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        // Parse here so only the `Sendable` release ID crosses to the main actor; `response` and
        // `completionHandler` stay in this method. The presentation runs on the next main-actor
        // turn, which is enough for a tap that opens the app.
        let releaseID = Self.releaseID(from: response.notification.request.content.userInfo)
        Task { @MainActor in
            self.presentRelease(id: releaseID)
        }
        completionHandler()
    }
}
