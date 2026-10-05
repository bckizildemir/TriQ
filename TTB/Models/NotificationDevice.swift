import FirebaseFirestore
import Foundation

enum NotificationAuthorizationState: String, CaseIterable {
    case notDetermined
    case denied
    case authorized
}

struct NotificationDevice: Identifiable, Equatable {
    let id: String
    let fcmToken: String
    let localeCode: String
    let contentUpdatesEnabled: Bool
    let authorizationStatus: NotificationAuthorizationState
    let isPushEligible: Bool
    let platform: String
    let appVersion: String
    let lastRegisteredAt: Date

    init(
        id: String,
        fcmToken: String,
        localeCode: String,
        contentUpdatesEnabled: Bool,
        authorizationStatus: NotificationAuthorizationState,
        isPushEligible: Bool,
        platform: String = "ios",
        appVersion: String,
        lastRegisteredAt: Date = Date()
    ) {
        self.id = id
        self.fcmToken = fcmToken
        self.localeCode = localeCode
        self.contentUpdatesEnabled = contentUpdatesEnabled
        self.authorizationStatus = authorizationStatus
        self.isPushEligible = isPushEligible
        self.platform = platform
        self.appVersion = appVersion
        self.lastRegisteredAt = lastRegisteredAt
    }

    static func fromFirestore(_ data: [String: Any], id: String) -> NotificationDevice {
        NotificationDevice(
            id: id,
            fcmToken: data["fcmToken"] as? String ?? "",
            localeCode: data["localeCode"] as? String ?? AppLocalization.currentLanguageCode,
            contentUpdatesEnabled: data["contentUpdatesEnabled"] as? Bool ?? false,
            authorizationStatus: NotificationAuthorizationState(
                rawValue: data["authorizationStatus"] as? String ?? ""
            ) ?? .notDetermined,
            isPushEligible: data["isPushEligible"] as? Bool ?? false,
            platform: data["platform"] as? String ?? "ios",
            appVersion: data["appVersion"] as? String ?? "unknown",
            lastRegisteredAt: (data["lastRegisteredAt"] as? Timestamp)?.dateValue() ?? Date()
        )
    }

    func toFirestore() -> [String: Any] {
        [
            "fcmToken": fcmToken,
            "localeCode": localeCode,
            "contentUpdatesEnabled": contentUpdatesEnabled,
            "authorizationStatus": authorizationStatus.rawValue,
            "isPushEligible": isPushEligible,
            "platform": platform,
            "appVersion": appVersion,
            "lastRegisteredAt": Timestamp(date: lastRegisteredAt),
        ]
    }
}
