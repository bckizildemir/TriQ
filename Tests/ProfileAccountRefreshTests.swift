import Testing
@testable import TTB

/// A guest upgrade keeps the uid, so nothing else in the app notices it: Profile runs the reloads
/// itself. The badge section used to be left out of that list, so it stayed empty until Profile
/// reappeared (#121).
@MainActor
struct ProfileAccountRefreshTests {
    @Test func aGuestUpgradeRunsTheProfileStatisticsAndBadgeReloadsInOrder() async {
        var performed: [ProfileAccountRefresh] = []

        await ProfileAccountRefresh.run(isAnonymous: false) { reload in
            performed.append(reload)
        }

        #expect(performed == [.profile, .statistics, .badges])
    }

    @Test func aGuestRunsNoReloads() async {
        var performed: [ProfileAccountRefresh] = []

        await ProfileAccountRefresh.run(isAnonymous: true) { reload in
            performed.append(reload)
        }

        #expect(performed.isEmpty)
    }
}
