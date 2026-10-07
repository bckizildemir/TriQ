import Foundation
import Testing
@testable import TTB

/// Each `@MainActor` model removes its listeners in an `isolated deinit`. These tests release the
/// model and check that every listener it held was removed. `QuestionModel` has its own suite.
@MainActor
struct ModelListenerCleanupTests {
    @Test func releasingFavoriteStoreCancelsTheFavoritesListener() async {
        let service = FakeFavoriteService()
        var store: FavoriteStore? = FavoriteStore(
            service: service,
            guestFavorites: GuestFavoriteModel(
                storage: UserDefaults(suiteName: "ModelListenerCleanupTests.\(UUID().uuidString)")!
            ),
            resolveQuestions: { _ in [] }
        )
        await store?.setIdentity(.account(userId: "user-1"))
        weak let releasedStore = store

        store = nil

        #expect(releasedStore == nil)
        #expect(service.handles.map(\.isCancelled) == [true])
    }

    @Test func releasingAuthModelRemovesTheAuthStateListener() {
        let auth = MockAuthProvider()
        var model: AuthModel? = makeAuthModelForTesting(auth: auth, registersAuthListener: true).0
        weak let releasedModel = model

        model = nil

        #expect(releasedModel == nil)
        #expect(auth.removeStateDidChangeListenerCallCount == 1)
    }

    @Test func releasingQuestionListStoreRemovesTheListsListener() {
        let listener = MockQuestionListListenerRegistration()
        var store: QuestionListStore? = QuestionListStore(localLists: [])
        store?.installListenerForTesting(listener)
        weak let releasedStore = store

        store = nil

        #expect(releasedStore == nil)
        #expect(listener.isRemoved)
    }

    @Test func releasingSharedQuestionListStoreRemovesBothShareListeners() {
        let owned = RecordingListenerHandle()
        let accepted = RecordingListenerHandle()
        var store: SharedQuestionListStore? = SharedQuestionListStore(localOwnedShares: [])
        store?.installListenersForTesting(ownedShares: owned, acceptedRecipients: accepted)
        weak let releasedStore = store

        store = nil

        #expect(releasedStore == nil)
        #expect(owned.isRemoved)
        #expect(accepted.isRemoved)
    }

    @Test(.timeLimit(.minutes(1)))
    func releasingAIModelRemovesTheQueriesListener() async {
        let listener = MockQuestionListListenerRegistration()
        var model: AIModel? = AIModel(
            aiService: MockAIService(),
            usageService: MockAIUsageService(),
            isAnonymousUser: { false }
        )
        model?.installQueriesListenerForTesting(listener)
        weak let releasedModel = model

        model = nil
        // `init` starts an unstructured initial load that holds the model until it ends; with no
        // signed-in user it ends after the mock usage read.
        while releasedModel != nil {
            await Task.yield()
        }

        #expect(releasedModel == nil)
        #expect(listener.isRemoved)
    }

    @Test func releasingCategoryModelRemovesTheCategoriesListener() {
        let listener = MockQuestionListListenerRegistration()
        var model: CategoryModel? = CategoryModel(localCategories: [])
        model?.installListenerForTesting(listener)
        weak let releasedModel = model

        model = nil

        #expect(releasedModel == nil)
        #expect(listener.isRemoved)
    }

    @Test func releasingBadgeModelRemovesTheUserDocumentListener() {
        let listener = RecordingListenerHandle()
        var model: BadgeModel? = BadgeModel(store: NoOpBadgeStore())
        model?.installUserListenerForTesting(listener)
        weak let releasedModel = model

        model = nil

        #expect(releasedModel == nil)
        #expect(listener.isRemoved)
    }

    @Test func releasingAdminReleaseManagerModelRemovesTheReleasesListener() {
        let listener = MockQuestionListListenerRegistration()
        var model: AdminReleaseManagerModel? = AdminReleaseManagerModel()
        model?.installListenerForTesting(listener)
        weak let releasedModel = model

        model = nil

        #expect(releasedModel == nil)
        #expect(listener.isRemoved)
    }
}

/// One fake for the two TTB handle protocols whose only requirement is `remove()`.
private final class RecordingListenerHandle: QuestionListShareListenerHandle, BadgeUserListening {
    private(set) var isRemoved = false

    func remove() {
        isRemoved = true
    }
}
