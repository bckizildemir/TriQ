import Foundation
import Testing
@testable import TTB

/// The device-document logic `NotificationService` keeps beside its Firebase calls: the snapshot
/// listener's mapping and main-actor hop, and the first read after sign-in. Tested without Firebase.
@Suite(.timeLimit(.minutes(1)))
struct NotificationDeviceSnapshotTests {
    @Test func theFlagIsReadFromTheDocument() {
        #expect(NotificationService.contentUpdatesEnabled(
            data: ["contentUpdatesEnabled": true],
            documentID: "device"
        ) == true)
        #expect(NotificationService.contentUpdatesEnabled(
            data: ["contentUpdatesEnabled": false],
            documentID: "device"
        ) == false)
    }

    @Test func aDocumentWithoutTheFlagIsOff() {
        #expect(NotificationService.contentUpdatesEnabled(data: [:], documentID: nil) == false)
    }

    @Test func aMissingDocumentIsNoUpdate() {
        #expect(NotificationService.contentUpdatesEnabled(data: nil, documentID: "device") == nil)
    }

    @Test func aDeliveredFlagRunsOnTheMainActor() async {
        let isEnabled: Bool = await withCheckedContinuation { continuation in
            NotificationService.deliverDeviceSnapshot(
                data: ["contentUpdatesEnabled": true],
                documentID: "device"
            ) { isEnabled in
                MainActor.assertIsolated()
                continuation.resume(returning: isEnabled)
            }
        }

        #expect(isEnabled)
    }

    @Test func aMissingDocumentDeliversNothing() async {
        let counter = DeliveryCounter()
        NotificationService.deliverDeviceSnapshot(data: nil, documentID: nil) { _ in
            counter.count += 1
        }
        // A delivery would hop to the main actor first; this later hop runs after it.
        await MainActor.run {}
        await Task.yield()

        #expect(await counter.count == 0)
    }

    @Test func theFirstReadUsesTheStoredFlagWhenTheDocumentExists() {
        #expect(NotificationService.initialContentUpdatesEnabled(
            existingData: ["contentUpdatesEnabled": false],
            installationID: "install",
            authorizationStatus: .authorized
        ) == false)
        #expect(NotificationService.initialContentUpdatesEnabled(
            existingData: ["contentUpdatesEnabled": true],
            installationID: "install",
            authorizationStatus: .denied
        ) == true)
    }

    @Test(arguments: [
        (NotificationAuthorizationState.authorized, true),
        (.denied, false),
        (.notDetermined, false),
    ])
    func theFirstReadFollowsAuthorizationWhenThereIsNoDocument(
        status: NotificationAuthorizationState,
        expected: Bool
    ) {
        #expect(NotificationService.initialContentUpdatesEnabled(
            existingData: nil,
            installationID: "install",
            authorizationStatus: status
        ) == expected)
    }
}

@MainActor
private final class DeliveryCounter {
    var count = 0
}
