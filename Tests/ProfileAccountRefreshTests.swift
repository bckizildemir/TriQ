import Testing
@testable import TTB

/// A guest upgrade keeps the uid, so nothing else in the app notices it: Profile runs the reloads
/// itself. The badge section used to be left out of that list, so it stayed empty until Profile
/// reappeared (#121).
struct ProfileAccountRefreshTests {
    @Test func aGuestUpgradeReloadsTheBadges() {
        #expect(ProfileAccountRefresh.onGuestUpgrade.contains(.badges))
    }

    @Test func aGuestUpgradeReloadsTheProfileAndItsStatistics() {
        #expect(ProfileAccountRefresh.onGuestUpgrade.contains(.profile))
        #expect(ProfileAccountRefresh.onGuestUpgrade.contains(.statistics))
    }

    /// A reload added later has to be a deliberate decision: the upgrade plan covers every reload
    /// Profile knows about, so a new one cannot be dropped from the upgrade path by accident.
    @Test func theUpgradePlanCoversEveryReload() {
        let plan = Set(ProfileAccountRefresh.onGuestUpgrade)
        let everyReload = Set(ProfileAccountRefresh.allCases)

        #expect(plan == everyReload)
    }
}
