import SwiftUI
import XCTest
@testable import TTB

/// Who decides whether a screen gets a live service.
///
/// Before AD-3's second half, five production files asked `UITestLaunchOptions` that question
/// themselves — a view initializer, an environment-key default and a port's default argument. The
/// decision belongs to whoever wires the app, so it sits on `AppEnvironment`: `live()` supplies the
/// real services and `uiTest()` supplies none.
///
/// The optionality itself stays. `aiService == nil` is a designed no-AI fallback rather than "do not
/// construct", so replacing it with a fake would change what the editor shows. `docs/adr/0005` names
/// AD-5 as the owner of removing it.
@MainActor
final class AppEnvironmentServiceSlotTests: XCTestCase {

    // MARK: - What a harness gets

    func testAHarnessEnvironmentHasNoAIService() {
        XCTAssertNil(harnessEnvironment().aiService)
    }

    func testAHarnessEnvironmentHasNoAnswerImageSuggestionService() {
        XCTAssertNil(harnessEnvironment().answerImageSuggestionService)
    }

    func testAHarnessEnvironmentHasNoAnswerPersister() {
        XCTAssertNil(harnessEnvironment().answerPersister)
    }

    // MARK: - What the environment assembles

    /// The environment owns the store, so the persister it was wired with is the one that saves.
    /// Before this, the store came from an environment-key default that asked a launch argument.
    func testTheEnvironmentSavesThroughItsOwnPersister() async throws {
        let persister = FakeAnswerPersister()
        let store = environment(answerPersister: persister).answerDraftStore
        let host = FakeAnswerHost()

        let plan = try XCTUnwrap(
            store.plan(
                for: .fixture(["One", "", ""]),
                baseline: .empty,
                questionId: "q-1",
                in: host
            )
        )
        store.applyOptimistically(plan, in: host)
        await store.finish(plan, in: host)

        let saveCount = await persister.saveCount
        XCTAssertEqual(saveCount, 1)
        XCTAssertEqual(host.normalized("q-1")?.texts.first, "One")
    }

    // MARK: - What a screen gets with no environment

    /// The direction the default points is the whole safety argument. A screen that renders outside
    /// `appEnvironment(_:)` must get an inert service, never a live one — `docs/adr/0005`'s shape.
    func testAScreenWithNoEnvironmentGetsNoAIService() {
        XCTAssertNil(EnvironmentValues().aiService)
    }

    func testAScreenWithNoEnvironmentGetsNoAnswerImageSuggestionService() {
        XCTAssertNil(EnvironmentValues().answerImageSuggestionService)
    }

    // MARK: - The badge model's store, FIX-6

    /// `uiTest()` wires `badgeModel` to `NoOpBadgeStore`, not to a `nil` slot: the two
    /// `@StateObject` construction sites (`ProfileView`, `AnswersContentView`) need a concrete
    /// instance, so the fixture has to be the store behind it rather than an absent `BadgeModel`.
    ///
    /// The store comes off `harnessEnvironment().badgeModel`, not from a fresh `NoOpBadgeStore()`,
    /// so this fails the moment `AppEnvironment.uiTest` wires a live store or drops the argument and
    /// falls back to `LiveBadgeStore` — the exact regression FIX-6 exists to catch. It then proves
    /// that store never reaches Firestore: every read comes back empty, every write is discarded,
    /// and `observeUserDocument` calls back once, synchronously, with no data, instead of leaving a
    /// live listener registered.
    func testAHarnessEnvironmentBadgeStoreTouchesNoFirestore() async throws {
        let store = harnessEnvironment().badgeModel.storeForTesting

        let userDocument = try await store.getUserDocument(userId: "service-slot-test-user")
        XCTAssertFalse(userDocument.exists)
        XCTAssertTrue(userDocument.data.isEmpty)

        try await store.setUserDocument(userId: "service-slot-test-user", data: ["a": 1], merge: true)

        let definitions = try await store.getBadgeDefinitionDocuments()
        XCTAssertTrue(definitions.isEmpty)

        var received: Result<[String: Any]?, Error>?
        let listener = store.observeUserDocument(userId: "service-slot-test-user") { received = $0 }
        listener.remove()

        switch try XCTUnwrap(received) {
        case .success(let data):
            XCTAssertNil(data)
        case .failure(let error):
            XCTFail("Expected success, got \(error)")
        }
    }

    // MARK: - Helpers

    /// The app's own wiring, with fakes where `live()` would reach Firebase — `badgeModel` included,
    /// so a test built on this helper never opens a real Firestore listener by omission.
    private func environment(answerPersister: AnswerPersisting?) -> AppEnvironment {
        AppEnvironment(
            authModel: UITestAuthModelFactory.permanentUser(uid: "service-slot-test-user"),
            questionModel: QuestionModel(localQuestions: []),
            answerModel: AnswerModel(),
            guestFavoriteModel: GuestFavoriteModel(storage: UserDefaults(suiteName: #function) ?? .standard),
            questionListStore: QuestionListStore(localLists: []),
            sharedQuestionListStore: SharedQuestionListStore(localOwnedShares: []),
            profileModel: ProfileModel(
                userId: "service-slot-test-user",
                startsAuthListener: false,
                loadsRemoteData: false
            ),
            categoryModel: CategoryModel(localCategories: []),
            notificationService: .shared,
            deepLinkRouter: AppDeepLinkRouter(),
            services: AppEnvironmentServices(
                aiService: nil,
                answerImageSuggestionService: nil,
                answerPersister: answerPersister
            ),
            badgeModel: BadgeModel(store: NoOpBadgeStore())
        )
    }

    private func harnessEnvironment() -> AppEnvironment {
        AppEnvironment.uiTest(
            storage: UserDefaults(suiteName: #function) ?? .standard,
            authModel: UITestAuthModelFactory.permanentUser(uid: "service-slot-test-user"),
            questionModel: QuestionModel(localQuestions: [])
        )
    }
}
