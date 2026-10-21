@testable import TTB

/// A `QuestionFeedListening` with no Firebase. Each setup call records a registration and its
/// completion. A feed in `held` suspends every call until the test releases it, so a test decides
/// the order in which overlapping calls finish.
actor FakeQuestionFeedListener: QuestionFeedListening {
    enum Feed: Hashable {
        case seeded, featuredHome, trio
    }

    typealias QuestionsCompletion = @MainActor @Sendable ([Question]) -> Void

    private let held: Set<Feed>
    private var registrationsByFeed: [Feed: [MockQuestionListListenerRegistration]] = [:]
    private var completionsByFeed: [Feed: [QuestionsCompletion]] = [:]
    private var gates: [Feed: [CheckedContinuation<Void, Never>]] = [:]
    private var heldWaiters: [(feed: Feed, count: Int, continuation: CheckedContinuation<Void, Never>)] = []

    init(holding held: Set<Feed> = []) {
        self.held = held
    }

    func registrations(for feed: Feed) -> [MockQuestionListListenerRegistration] {
        registrationsByFeed[feed] ?? []
    }

    func completions(for feed: Feed) -> [QuestionsCompletion] {
        completionsByFeed[feed] ?? []
    }

    /// Returns once `count` calls to `feed` are suspended at the gate.
    func waitUntilHeld(_ feed: Feed, count: Int) async {
        if gates[feed, default: []].count >= count { return }
        await withCheckedContinuation { continuation in
            heldWaiters.append((feed, count, continuation))
        }
    }

    /// Lets the call at `index` (arrival order) of `feed` return.
    func release(_ feed: Feed, at index: Int) {
        gates[feed]?[index].resume()
    }

    func setupSeededQuestionsListener(
        completion: @escaping QuestionsCompletion
    ) async -> FirestoreListenerHandle {
        await record(.seeded, completion: completion)
    }

    func setupFeaturedHomeQuestionsListener(
        completion: @escaping QuestionsCompletion
    ) async -> FirestoreListenerHandle {
        await record(.featuredHome, completion: completion)
    }

    func setupTrioQuestionsListener(
        completion: @escaping QuestionsCompletion
    ) async -> FirestoreListenerHandle {
        await record(.trio, completion: completion)
    }

    func setupUserAnswersListener(
        completion: @escaping @MainActor @Sendable ([String: UserAnswer]) -> Void
    ) async -> FirestoreListenerHandle? {
        nil
    }

    private func record(_ feed: Feed, completion: @escaping QuestionsCompletion) async -> FirestoreListenerHandle {
        let registration = MockQuestionListListenerRegistration()
        registrationsByFeed[feed, default: []].append(registration)
        completionsByFeed[feed, default: []].append(completion)
        if held.contains(feed) {
            await withCheckedContinuation { continuation in
                gates[feed, default: []].append(continuation)
                let count = gates[feed, default: []].count
                let ready = heldWaiters.filter { $0.feed == feed && $0.count <= count }
                heldWaiters.removeAll { $0.feed == feed && $0.count <= count }
                for waiter in ready { waiter.continuation.resume() }
            }
        }
        return FirestoreListenerHandle(registration: registration)
    }
}
