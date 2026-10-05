import Foundation
import Testing
@testable import TTB

/// `AppLocalization.preferredLanguageCodes` is memoized behind a process-wide cache, and every card
/// body reads it, from whatever isolation the caller has. The cache must return exactly what the
/// uncached resolver returns, and must keep doing so when many callers read it at once.
struct PreferredLanguageCodesCacheTests {
    @Test func cachedCodesMatchTheUncachedResolver() {
        let expected = AppLocalization.preferredLanguageCodes(for: Locale.preferredLanguages)

        #expect(AppLocalization.preferredLanguageCodes == expected)
        #expect(AppLocalization.preferredLanguageCodes == expected)
    }

    @Test func concurrentReadersAllSeeTheSameCodes() async {
        let expected = AppLocalization.preferredLanguageCodes(for: Locale.preferredLanguages)

        let results = await withTaskGroup(of: [String].self) { group in
            for _ in 0..<64 {
                group.addTask { AppLocalization.preferredLanguageCodes }
            }

            var results: [[String]] = []
            for await codes in group {
                results.append(codes)
            }
            return results
        }

        #expect(results.count == 64)
        #expect(results.allSatisfy { $0 == expected })
    }
}
