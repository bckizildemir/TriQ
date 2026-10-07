import CryptoKit
import Foundation
import XCTest
@testable import TTB

/// Micro-benchmarks for the derivations that run on the app's hottest paths
/// (home render, favorite toggle, question search). These are re-runnable
/// before/after numbers for the memory & performance pass — they measure CPU
/// cost of pure derivations, not footprint and not real scroll smoothness.
///
/// Run with:
///   xcodebuild -project TTB.xcodeproj -scheme TTB \
///     -destination 'platform=iOS Simulator,name=iPhone 12,OS=26.5' \
///     -only-testing:TTBTests/HotPathBenchmarkTests test
final class HotPathBenchmarkTests: XCTestCase {

    private static let corpusSize = 1_000

    /// How many favorites the benchmarked account holds. The account branch of
    /// `FavoriteStore.refreshFavorites()` filters and sorts this list on every toggle, so it is
    /// what sets the cost — a heavy but not absurd user.
    private static let accountFavoriteCount = 200

    private lazy var corpus: [Question] = Self.makeCorpus(count: Self.corpusSize)

    // MARK: - Localization resolution (Question.text / Category.displayName)

    /// `Question.text` resolves the preferred-language list on every access, and
    /// `question.text` is read per card body and per item in every search filter.
    func testBenchmarkQuestionTextResolution() {
        let questions = corpus
        measure {
            var total = 0
            for question in questions {
                total += question.text.count
            }
            XCTAssertGreaterThan(total, 0)
        }
    }

    /// The raw preferred-language-code lookup that `Question.text` and
    /// `Category.displayName` both funnel through.
    func testBenchmarkPreferredLanguageCodes() {
        measure {
            for _ in 0 ..< 1_000 {
                _ = AppLocalization.preferredLanguageCodes
            }
        }
    }

    /// `CategoryModel.activeCategories` sorts on `displayName`, so every
    /// comparison resolves localized names for both operands.
    @MainActor
    func testBenchmarkActiveCategories() {
        let model = CategoryModel(localCategories: Category.defaultCategories)
        measure {
            for _ in 0 ..< 100 {
                _ = model.activeCategories
            }
        }
    }

    // MARK: - Today's questions selection

    /// Runs on every listener snapshot *and* on every favorite toggle.
    func testBenchmarkTodaysQuestionSelection() {
        let selector = TodaysQuestionSelector()
        let questions = corpus
        measure {
            _ = selector.select(from: questions, on: Date(timeIntervalSince1970: 1_774_627_200))
        }
    }

    // MARK: - Favorite toggle fan-out

    /// One star tap used to re-map four arrays, regroup, re-sort and re-select today's questions,
    /// because `QuestionModel` patched `isFavorite` into six derived collections. `FavoriteStore`
    /// owns the state instead, so a toggle now touches one dictionary and rebuilds one list — this
    /// measures that list rebuild, which is all that is left of the fan-out.
    ///
    /// The store has to be an account with a snapshot loaded. `FavoriteStore.previews` is
    /// `.signedOut`, and both `toggle` and `state(of:)` short-circuit on that before they reach the
    /// ladder — measuring the guard instead of the work. See `makeAccountStore`.
    @MainActor
    func testBenchmarkFavoriteToggleFanOut() {
        let store = makeAccountStore(favorites: Array(corpus.prefix(Self.accountFavoriteCount)))
        // Deliberately outside the snapshot, so each iteration adds a question to the rebuilt list
        // and the next removes it — the same work in both directions.
        let target = corpus[corpus.count / 2]
        measure {
            let expectation = expectation(description: "toggle")
            Task { @MainActor in
                await store.toggle(target)
                expectation.fulfill()
            }
            wait(for: [expectation], timeout: 5)
        }
    }

    // MARK: - Per-card favorite lookup

    /// `QuestionCard.isFavorite` reads the store once per body evaluation, ~3x per card. Mirrors
    /// `QuestionCard.isFavorite` — keep the two in sync.
    ///
    /// Account identity for the same reason as the toggle benchmark: signed out, `state(of:)`
    /// returns the `isFavorite` flag decoded onto the question, which is a stored-property read
    /// rather than the pending-write/snapshot/seed ladder a real card pays for.
    @MainActor
    func testBenchmarkPerCardFavoriteLookup() {
        let store = makeAccountStore(favorites: Array(corpus.prefix(Self.accountFavoriteCount)))
        let visibleCards = Array(corpus.prefix(40))
        measure {
            var favorites = 0
            // 3 reads per card body, matching QuestionCard's body.
            for _ in 0 ..< 3 {
                for card in visibleCards where store.state(of: card) {
                    favorites += 1
                }
            }
            XCTAssertGreaterThanOrEqual(favorites, 0)
        }
    }

    /// `question(withID:)` is called once per entry when resolving a question list.
    @MainActor
    func testBenchmarkQuestionLookupByID() {
        let model = QuestionModel(localQuestions: corpus)
        let ids = corpus.map(\.id)
        measure {
            var found = 0
            for id in ids where model.question(withID: id) != nil {
                found += 1
            }
            XCTAssertEqual(found, ids.count)
        }
    }

    // MARK: - Question search

    /// Every keystroke in the question-list picker filters the whole corpus,
    /// reading `question.text` per item.
    func testBenchmarkQuestionSearchFilter() {
        let questions = corpus
        measure {
            let matches = questions.filter { $0.text.localizedCaseInsensitiveContains("progress") }
            XCTAssertGreaterThanOrEqual(matches.count, 0)
        }
    }

    // MARK: - Paired before/after benchmarks
    //
    // Absolute timings drift a lot with machine state (the same unchanged code measured 16 ms and
    // 35 ms on this machine hours apart), so comparing a "before" run against a later "after" run is
    // not sound. These reimplement the pre-optimization algorithm alongside the current one so both
    // are measured in the same process, and the *ratio* is the trustworthy number.

    /// Pre-optimization: the SHA-256 digest formatted as a 64-character hex string via 32
    /// `String(format:)` calls per question, decorating whole `Question` values before the sort.
    func testBenchmarkBaseline_TodaysQuestionSelectionViaHexRanking() {
        let questions = corpus
        let date = Date(timeIntervalSince1970: 1_774_627_200)
        measure {
            _ = Self.hexRankedSelection(from: questions, on: date, count: 7)
        }
    }

    /// Pre-optimization: resolved from scratch on every access.
    func testBenchmarkBaseline_PreferredLanguageCodesUncached() {
        let preferredLanguages = Locale.preferredLanguages
        measure {
            for _ in 0 ..< 1_000 {
                _ = AppLocalization.preferredLanguageCodes(for: preferredLanguages)
            }
        }
    }

    /// Pre-optimization: `QuestionCard.isFavorite` scanned the whole corpus per card.
    @MainActor
    func testBenchmarkBaseline_PerCardFavoriteLookupByLinearScan() {
        let model = QuestionModel(localQuestions: corpus)
        let visibleCards = Array(corpus.prefix(40))
        measure {
            var favorites = 0
            for _ in 0 ..< 3 {
                for card in visibleCards
                where model.questions.first(where: { $0.id == card.id })?.isFavorite == true {
                    favorites += 1
                }
            }
            XCTAssertGreaterThanOrEqual(favorites, 0)
        }
    }

    private static func hexRankedSelection(
        from questions: [Question],
        on date: Date,
        count: Int
    ) -> [Question] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        let dayKey = String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )

        var ranked: [(question: Question, rank: String)] = []
        for question in questions where question.source == .seeded {
            let payload: String = "\(dayKey)|\(question.contentId)"
            let digest = SHA256.hash(data: Data(payload.utf8))
            let hex: String = digest.map { byte in String(format: "%02x", byte) }.joined()
            ranked.append((question: question, rank: hex))
        }

        ranked.sort { lhs, rhs in
            if lhs.rank == rhs.rank {
                return lhs.question.contentId < rhs.question.contentId
            }
            return lhs.rank < rhs.rank
        }

        return ranked.prefix(count).map(\.question)
    }

    // MARK: - Fixtures

    /// A store on `.account` with `favorites` already snapshotted, so the favorite benchmarks
    /// measure the precedence ladder rather than the signed-out guard.
    ///
    /// `setIdentity` is async and `measure` is not, so the setup runs through the same
    /// expectation-and-wait pattern the toggle benchmark uses — once, here, outside the measured
    /// block.
    @MainActor
    private func makeAccountStore(favorites: [Question]) -> FavoriteStore {
        let service = FakeFavoriteService()
        let store = FavoriteStore(
            service: service,
            guestFavorites: GuestFavoriteModel(
                storage: UserDefaults(suiteName: "HotPathBenchmarkTests.\(UUID().uuidString)")!
            ),
            resolveQuestions: { _ in [] }
        )

        let ready = expectation(description: "account snapshot")
        Task { @MainActor in
            await store.setIdentity(.account(userId: "benchmark-user"))
            service.emit(favorites)
            ready.fulfill()
        }
        wait(for: [ready], timeout: 5)

        return store
    }

    private static func makeCorpus(count: Int) -> [Question] {
        let categories = Category.defaultCategories.map(\.id)
        return (0 ..< count).map { index in
            Question(
                id: "question-\(index)",
                text: "Benchmark question number \(index) about progress and plans",
                category: categories[index % categories.count],
                localizedTexts: [
                    "en": "Benchmark question number \(index) about progress and plans",
                    "tr": "Kıyaslama sorusu \(index) — ilerleme ve planlar"
                ],
                languageCode: "en",
                createdAt: Date(timeIntervalSince1970: 1_700_000_000 + Double(index))
            )
        }
    }
}
