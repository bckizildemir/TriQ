import Testing
@testable import TTB

/// Home and the profile screen share one app-wide `ProfileModel` (#70), so state that a screen
/// leaves behind outlives it. These tests cover the state that must not leak between presentations.
@MainActor
struct ProfileModelSharedStateTests {
    private static func makeModel() -> ProfileModel {
        ProfileModel(
            uiTestUsername: "saved-name",
            email: "saved@example.com",
            statistics: .init(daily: 1, weekly: 2, total: 3)
        )
    }

    /// The invalid email fails before any Firebase call, so this reaches the failure path offline.
    @Test func failedSaveRestoresTheSavedUsernameAndEmail() async {
        let model = Self.makeModel()
        model.username = "unsaved-name"
        model.email = "not-an-email"

        await model.updateProfile()

        #expect(model.showingAlert)
        #expect(model.username == "saved-name")
        #expect(model.email == "saved@example.com")
    }

    /// An alert flag that no screen showed (a failed load at launch) must not stay `true`: the
    /// profile screen only shows an alert when the flag changes, and Edit Profile would replay it.
    @Test func presentingTheProfileClearsAStaleAlertFlag() async {
        let model = Self.makeModel()
        model.alertMessage = "Old load error"
        model.showingAlert = true

        await model.refreshForPresentation()

        #expect(!model.showingAlert)
    }

    /// A UI-test fixture model has no remote data, so presenting it keeps its fixture counters.
    @Test func presentingAFixtureModelKeepsItsStatistics() async {
        let model = Self.makeModel()

        await model.refreshForPresentation()

        #expect(model.statistics.daily == 1)
        #expect(model.statistics.weekly == 2)
        #expect(model.statistics.total == 3)
    }
}
