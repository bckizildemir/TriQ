import Foundation
import os

/// What a favorite toggle settled on.
enum FavoriteToggleOutcome: Equatable {
    case added
    case removed
    /// The guest favorite cap is now in force — either this toggle stored the favorite that reached
    /// the cap, or the cap blocked it. Either way the one UI consequence, the signup prompt, rides
    /// this outcome rather than a flag the guest store publishes on the side. Never for an account.
    case guestLimitReached
    /// Nothing was saved. The store has already rolled its optimistic state back and published
    /// `error`, so a caller that ignores this loses no correctness — it is returned so the
    /// failure is visible to tests and to any caller that wants to react.
    case failed
}

/// Whose favorites the store is holding.
///
/// Guest and account favorites live in different places with different rules, and this is the
/// only thing that decides which. Callers never branch on it: they ask `state(of:)`.
enum FavoriteIdentity: Equatable {
    case signedOut
    case guest
    case account(userId: String)

    /// The single rule for deriving who favorites belong to from auth state, so the app root and
    /// every UI-test harness agree. A harness that skips this leaves the store signed out, and
    /// every toggle silently fails.
    static func resolved(
        isAuthenticated: Bool,
        isAnonymous: Bool,
        userId: String?
    ) -> FavoriteIdentity {
        guard isAuthenticated, let userId, !userId.isEmpty else { return .signedOut }
        return isAnonymous ? .guest : .account(userId: userId)
    }
}

/// Turns favorite ids into questions.
///
/// Guest favorites are stored as ids alone, so rendering them needs the question corpus. This
/// one function is the whole of the store's dependency on it — deliberately not `QuestionModel`,
/// which would couple every favorite to the largest object in the app.
typealias QuestionResolving = @MainActor ([String]) -> [Question]

enum FavoriteStoreError: LocalizedError {
    case notSignedIn

    var errorDescription: String? {
        switch self {
        case .notSignedIn:
            return String(localized: "favorite.error.notSignedIn")
        }
    }
}

/// Owns favorite state for guests and accounts alike.
///
/// The interface is deliberately two methods and one list. Everything that used to be spread
/// across three view-local resolvers and two override engines lives here instead:
///
/// - **The precedence ladder.** An account's favorite state is a pending optimistic write if
///   there is one, else membership in the backend snapshot, else the `isFavorite` flag decoded
///   onto the question. That last rung is why the old code OR-ed two stores together: before the
///   favorites snapshot arrives, the decoded flag is the only thing that knows. It is a seed, not
///   a source — the store never writes it back, and staleness cannot show because the two rungs
///   above it win.
/// - **Optimism and rollback.** A toggle applies immediately, then reconciles against what the
///   backend settled on, and rolls back if the write failed.
/// - **Guest rules.** The cap, the milestone and the upgrade prompts stay in `GuestFavoriteModel`,
///   which sits behind this seam as the guest adapter. Presentation of those signals is the
///   root's job, not this store's.
@MainActor
final class FavoriteStore: ObservableObject {
    /// Ordered for display. Guest favorites keep the order they were saved in; account favorites
    /// are newest-first. The difference is inherited deliberately — it is what each screen showed
    /// before this store owned the list, and changing it is a product decision, not a refactor.
    @Published private(set) var favorites: [Question] = []
    /// True while an account's first snapshot is outstanding. Guests are never loading: their
    /// favorites are on the device.
    @Published private(set) var isLoading = false
    @Published var error: String?

    private let service: FavoriteServicing
    private let guestFavorites: GuestFavoriteModel
    private let resolveQuestions: QuestionResolving
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.ttb.app",
        category: "FavoriteStore")

    private var identity: FavoriteIdentity = .signedOut
    private var listener: FavoriteListenerHandle?

    /// The backend's answer, before optimistic states are layered on.
    private var snapshotQuestions: [Question] = []
    private var snapshotIDs: Set<String> = []
    private var hasSnapshot = false

    /// Optimistic states no snapshot has confirmed yet, and the questions they added — kept
    /// because a question favorited from the corpus is not in the snapshot until the backend
    /// catches up, and the list has to show it now.
    private var pendingStates: [String: Bool] = [:]
    private var pendingQuestions: [String: Question] = [:]

    init(
        service: FavoriteServicing,
        guestFavorites: GuestFavoriteModel,
        resolveQuestions: @escaping QuestionResolving
    ) {
        self.service = service
        self.guestFavorites = guestFavorites
        self.resolveQuestions = resolveQuestions
    }

    deinit {
        listener?.cancel()
    }

    // MARK: - Reads

    /// Whether this question is a favorite, from whichever source currently owns the answer.
    ///
    /// Takes the question rather than an id so the caller supplies the seed rung of the ladder;
    /// that is what keeps the corpus out of this type.
    func state(of question: Question) -> Bool {
        switch identity {
        case .signedOut:
            return question.isFavorite
        case .guest:
            return guestFavorites.isFavorite(questionId: question.id)
        case .account:
            if let pendingState = pendingStates[question.id] {
                return pendingState
            }
            guard hasSnapshot else { return question.isFavorite }
            return snapshotIDs.contains(question.id)
        }
    }

    // MARK: - Identity

    /// Points the store at a different owner, tearing down whatever the previous one had.
    ///
    /// Every optimistic state is dropped: a pending write belongs to the user who made it. The
    /// listener is re-registered under the new id, and a registration that completes after
    /// another identity change is cancelled rather than kept — otherwise it keeps publishing the
    /// previous user's favorites.
    func setIdentity(_ newIdentity: FavoriteIdentity) async {
        guard newIdentity != identity else { return }

        identity = newIdentity
        listener?.cancel()
        listener = nil
        snapshotQuestions = []
        snapshotIDs = []
        hasSnapshot = false
        pendingStates = [:]
        pendingQuestions = [:]
        error = nil

        switch newIdentity {
        case .signedOut, .guest:
            isLoading = false
            refreshFavorites()
        case .account(let userId):
            favorites = []
            isLoading = true
            await startListener(userId: userId)
        }
    }

    private func startListener(userId: String) async {
        let handle = await service.favoritesListener(userId: userId) { [weak self] result in
            self?.applySnapshot(result, for: userId)
        }

        guard identity == .account(userId: userId) else {
            handle.cancel()
            return
        }
        listener = handle
    }

    private func applySnapshot(_ result: Result<[Question], Error>, for userId: String) {
        guard identity == .account(userId: userId) else { return }

        isLoading = false

        switch result {
        case .success(let questions):
            snapshotQuestions = questions
            snapshotIDs = Set(questions.map(\.id))
            hasSnapshot = true
            reconcilePendingStates()
            refreshFavorites()
            error = nil
        case .failure(let failure):
            error = failure.localizedDescription
        }
    }

    /// Drops optimistic states the snapshot now agrees with. Anything still pending is a write
    /// the backend has not reflected yet, so it keeps winning.
    private func reconcilePendingStates() {
        for (questionId, pendingState) in pendingStates
        where snapshotIDs.contains(questionId) == pendingState {
            pendingStates.removeValue(forKey: questionId)
            pendingQuestions.removeValue(forKey: questionId)
        }
    }

    // MARK: - Writes

    /// Flips this question's favorite state.
    ///
    /// Applies immediately, then reconciles: the backend's answer wins over the optimistic guess,
    /// and a failure rolls the guess back and publishes `error`.
    @discardableResult
    func toggle(_ question: Question) async -> FavoriteToggleOutcome {
        switch identity {
        case .signedOut:
            error = FavoriteStoreError.notSignedIn.localizedDescription
            return .failed
        case .guest:
            let result = guestFavorites.toggleFavorite(questionId: question.id)
            refreshFavorites()
            switch result {
            case .added(let count):
                // The add that lands on the cap carries the limit forward so the consumer can
                // prompt without the guest store having to publish a flag of its own.
                return count >= GuestFavoriteModel.maxGuestFavorites ? .guestLimitReached : .added
            case .removed:
                return .removed
            case .limitReached:
                return .guestLimitReached
            case .unchanged:
                // Only reachable for an empty id, which is a caller bug rather than a state.
                return .failed
            }
        case .account(let userId):
            return await toggleForAccount(question, userId: userId)
        }
    }

    private func toggleForAccount(
        _ question: Question,
        userId: String
    ) async -> FavoriteToggleOutcome {
        let previousState = state(of: question)
        let desiredState = !previousState
        applyPendingState(desiredState, for: question)

        do {
            let settledState = try await service.toggle(
                questionId: question.id,
                userId: userId,
                currentState: previousState
            )
            guard identity == .account(userId: userId) else { return .failed }

            if settledState != desiredState {
                logger.debug("Favorite toggle settled on \(settledState) for question \(question.id)")
                applyPendingState(settledState, for: question)
            }
            error = nil
            return settledState ? .added : .removed
        } catch {
            guard identity == .account(userId: userId) else { return .failed }
            clearPendingState(for: question.id)
            self.error = error.localizedDescription
            return .failed
        }
    }

    /// Moves guest favorites onto an account.
    ///
    /// Safe to call repeatedly: the write is idempotent and an id is cleared from the device only
    /// once the server has actually accepted it, so the caller can retry on every foreground. An id
    /// the server reports unavailable stays on the device and is retried next time, per Guest
    /// Favorite's contract that a migration which does not succeed loses nothing. A failure is
    /// logged rather than published — this runs unprompted, and an alert on every retry would be
    /// noise. That silence is why a rules-rejected write went unnoticed here for months, so the log
    /// is the record.
    func migrateGuestFavorites(to userId: String) async {
        let questionIds = guestFavorites.guestFavorites
        guard !userId.isEmpty, !questionIds.isEmpty else { return }

        do {
            let unavailableIds = try await service.addFavorites(questionIds: questionIds)
            guestFavorites.completeMigration(unavailableQuestionIds: unavailableIds)
            refreshFavorites()
        } catch {
            logger.error("Guest favorite migration failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Derivation

    private func applyPendingState(_ state: Bool, for question: Question) {
        pendingStates[question.id] = state
        if state {
            pendingQuestions[question.id] = question
        } else {
            pendingQuestions.removeValue(forKey: question.id)
        }
        refreshFavorites()
    }

    private func clearPendingState(for questionId: String) {
        pendingStates.removeValue(forKey: questionId)
        pendingQuestions.removeValue(forKey: questionId)
        refreshFavorites()
    }

    /// Single funnel for `favorites`, so the published list cannot drift from the state the
    /// ladder reports.
    private func refreshFavorites() {
        switch identity {
        case .signedOut:
            favorites = []
        case .guest:
            favorites = resolveQuestions(guestFavorites.guestFavorites)
        case .account:
            var questions = snapshotQuestions.filter { pendingStates[$0.id] != false }
            let presentIDs = Set(questions.map(\.id))
            for (questionId, question) in pendingQuestions
            where pendingStates[questionId] == true && !presentIDs.contains(questionId) {
                questions.append(question)
            }
            favorites = questions.sorted { $0.createdAt > $1.createdAt }
        }
    }
}

// MARK: - Previews

/// Null adapter: satisfies the seam without a backend, so a preview can render favorite chrome
/// without Firebase. Not a test double — tests use the in-memory fake, which actually behaves.
private struct UnavailableFavoriteService: FavoriteServicing {
    func favoritesListener(
        userId: String,
        onChange: @escaping @MainActor @Sendable (Result<[Question], Error>) -> Void
    ) -> FavoriteListenerHandle {
        Task { @MainActor in onChange(.success([])) }
        return UnavailableFavoriteListenerHandle()
    }

    func toggle(questionId: String, userId: String, currentState: Bool?) async throws -> Bool {
        throw FavoriteStoreError.notSignedIn
    }

    func addFavorites(questionIds: [String]) async throws -> Set<String> { [] }
}

private struct UnavailableFavoriteListenerHandle: FavoriteListenerHandle {
    func cancel() {}
}

extension FavoriteStore {
    /// A store with no backend: nothing favorited, writes refused. Previews render chrome.
    static var previews: FavoriteStore {
        FavoriteStore(
            service: UnavailableFavoriteService(),
            guestFavorites: GuestFavoriteModel(
                storage: UserDefaults(suiteName: "FavoriteStore.previews") ?? .standard
            ),
            resolveQuestions: { _ in [] }
        )
    }
}
