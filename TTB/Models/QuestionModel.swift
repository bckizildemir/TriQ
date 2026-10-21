import Combine
import FirebaseAuth
import FirebaseFirestore
import Foundation
import os

enum QuestionModelError: LocalizedError {
    case localModeUnsupported
    case questionNotFound(String)

    var errorDescription: String? {
        switch self {
        case .localModeUnsupported:
            return "This operation is not supported in QuestionModel local mode."
        case .questionNotFound(let questionId):
            return "Question not found: \(questionId)"
        }
    }
}

@MainActor
class QuestionModel: ObservableObject {
    @Published private(set) var questions: [Question] = []
    @Published private(set) var groupedQuestions: [String: [Question]] = [:]
    @Published private(set) var todaysQuestions: [Question] = []
    @Published private(set) var trioQuestions: [Question] = []
    @Published private(set) var isLoading = false
    @Published var error: String?

    /// All answers saved by the currently signed-in user, keyed by questionId.
    @Published private(set) var currentUserAnswers: [String: UserAnswer] = [:]

    private let questionService: QuestionService?
    /// Where the listeners come from: the same `QuestionService` in the app, a fake in tests, nil in local mode.
    private let listenerService: (any QuestionFeedListening)?
    private let todaysQuestionSelector: TodaysQuestionSelector
    private var seededQuestionsListener: FirestoreListenerHandle?
    private var featuredHomeQuestionsListener: FirestoreListenerHandle?
    private var trioListener: FirestoreListenerHandle?
    private var userAnswersListener: FirestoreListenerHandle?
    private var authStateHandle: AuthStateDidChangeListenerHandle?
    /// One generation per feed. Each setup call bumps its feed's generation before it awaits; when
    /// the service returns, a changed generation means a newer call took over, so the old handle is
    /// cancelled instead of stored (TriQ#50). Delivery closures capture the generation they were
    /// set up with and drop a delivery from a stale one.
    private var questionsListenerGeneration: UInt = 0
    private var trioListenerGeneration: UInt = 0
    private var userAnswersListenerGeneration: UInt = 0
    /// Bumped by `clearRemoteState()`. `startRemoteSession()` stops before each next setup step when
    /// it changed, so a sign-out during setup leaves no listener for the signed-out session (TriQ#52).
    private var remoteSessionGeneration: UInt = 0
    private var seededQuestions: [Question] = []
    private var featuredHomeQuestions: [Question] = []
    /// `id` -> index into `questions`, so per-card lookups don't scan the whole corpus. Maintained by
    /// `replaceQuestions(_:)`; every site that changes membership or order must go through it.
    /// In-place element edits (a favorite flag) leave the mapping valid and skip the rebuild.
    private var questionIndexByID: [String: Int] = [:]
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.ttb.app",
        category: "QuestionModel")

    init(
        questionService: QuestionService = QuestionService(),
        todaysQuestionSelector: TodaysQuestionSelector = TodaysQuestionSelector()
    ) {
        self.questionService = questionService
        listenerService = questionService
        self.todaysQuestionSelector = todaysQuestionSelector
        logger.debug("QuestionModel initialized")
        setupAuthListener()
    }

    init(
        localQuestions: [Question],
        localUserAnswers: [String: UserAnswer] = [:],
        todaysQuestionSelector: TodaysQuestionSelector = TodaysQuestionSelector()
    ) {
        questionService = nil
        listenerService = nil
        self.todaysQuestionSelector = todaysQuestionSelector
        replaceQuestions(localQuestions)
        currentUserAnswers = localUserAnswers
        updateGroupedQuestions()
    }

    /// Runs the listener setup against `listenerService` without `Auth.auth()`, so a test can drive it
    /// with a fake. Like `QuestionListStore`'s `observesAuth: false`.
    init(
        listenerService: any QuestionFeedListening,
        todaysQuestionSelector: TodaysQuestionSelector = TodaysQuestionSelector()
    ) {
        questionService = nil
        self.listenerService = listenerService
        self.todaysQuestionSelector = todaysQuestionSelector
    }

    /// `isolated` so the cleanup can read the main-actor listener handles. Below iOS 18.4 the
    /// compiler links a main-actor back-deploy shim, so this needs no deployment-target change.
    isolated deinit {
        seededQuestionsListener?.cancel()
        featuredHomeQuestionsListener?.cancel()
        trioListener?.cancel()
        userAnswersListener?.cancel()
        if let handle = authStateHandle {
            Auth.auth().removeStateDidChangeListener(handle)
        }
    }

    /// Re-subscribes user answers listener whenever the signed-in user changes.
    private func setupAuthListener() {
        authStateHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            guard let self = self else { return }
            Task { @MainActor in
                if user != nil {
                    await self.startRemoteSession()
                } else {
                    self.clearRemoteState()
                }
            }
        }
    }

    /// Sets up every listener for a signed-in user. Stops before the next step when a sign-out ran
    /// `clearRemoteState()` meanwhile, because each setup bumps its own fresh feed generation.
    func startRemoteSession() async {
        let session = remoteSessionGeneration
        logger.debug("Setting up question listeners")
        await setupQuestionsListener()
        guard remoteSessionGeneration == session else { return }
        await setupTrioQuestionsListener()
        guard remoteSessionGeneration == session else { return }
        await setupUserAnswersListener()
    }

    func clearRemoteState() {
        // Handles a setup call is still awaiting are not stored yet. Bumping the generations makes
        // that call cancel its handle on resume and makes a queued delivery drop itself.
        remoteSessionGeneration &+= 1
        questionsListenerGeneration &+= 1
        trioListenerGeneration &+= 1
        userAnswersListenerGeneration &+= 1
        seededQuestionsListener?.cancel()
        seededQuestionsListener = nil
        featuredHomeQuestionsListener?.cancel()
        featuredHomeQuestionsListener = nil
        trioListener?.cancel()
        trioListener = nil
        userAnswersListener?.cancel()
        userAnswersListener = nil
        replaceQuestions([])
        seededQuestions = []
        featuredHomeQuestions = []
        groupedQuestions = [:]
        todaysQuestions = []
        trioQuestions = []
        currentUserAnswers = [:]
        isLoading = false
        // An error from the old session must not carry into the next one.
        error = nil
    }

    private func setupUserAnswersListener() async {
        guard let listenerService else { return }
        userAnswersListenerGeneration &+= 1
        let generation = userAnswersListenerGeneration
        userAnswersListener?.cancel()
        userAnswersListener = nil
        let handle = await listenerService.setupUserAnswersListener { [weak self] answers in
            guard let self, userAnswersListenerGeneration == generation else { return }
            currentUserAnswers = answers
        }
        guard userAnswersListenerGeneration == generation else {
            handle?.cancel()
            return
        }
        userAnswersListener = handle
    }

    /// Returns the current user's saved answers for a specific question, or an empty array.
    func myAnswers(for questionId: String) -> [String] {
        currentUserAnswers[questionId]?.answers ?? []
    }

    /// Single funnel for changes to `questions`' membership or order, so the id index cannot drift.
    private func replaceQuestions(_ newQuestions: [Question]) {
        questions = newQuestions
        var index: [String: Int] = [:]
        index.reserveCapacity(newQuestions.count)
        // First occurrence wins, matching the `first(where:)` lookups this replaced.
        for (offset, question) in newQuestions.enumerated() where index[question.id] == nil {
            index[question.id] = offset
        }
        questionIndexByID = index
    }

    /// Returns the current user's saved image URLs for a specific question.
    /// Returns [nil, nil, nil] when no images have been saved.
    func myImageURLs(for questionId: String) -> [String?] {
        currentUserAnswers[questionId]?.imageURLs ?? [nil, nil, nil]
    }

    func myImageAttributions(for questionId: String) -> [AnswerImageAttribution?] {
        currentUserAnswers[questionId]?.imageAttributions ?? [nil, nil, nil]
    }

    func refreshQuestions() async {
        guard listenerService != nil else {
            updateGroupedQuestions()
            return
        }
        let session = remoteSessionGeneration
        await setupQuestionsListener()
        guard remoteSessionGeneration == session else { return }
        await setupTrioQuestionsListener()
    }

    private func setupQuestionsListener() async {
        guard let listenerService else { return }
        questionsListenerGeneration &+= 1
        let generation = questionsListenerGeneration
        isLoading = true
        seededQuestionsListener?.cancel()
        seededQuestionsListener = nil
        featuredHomeQuestionsListener?.cancel()
        featuredHomeQuestionsListener = nil

        let seededHandle = await listenerService.setupSeededQuestionsListener { [weak self] result in
            guard let self, questionsListenerGeneration == generation else { return }
            switch result {
            case .success(let questions):
                seededQuestions = questions
                updatePublicQuestions()
            case .failure(let failure):
                logger.error("Seeded questions failed to load: \(failure.localizedDescription)")
                error = failure.localizedDescription
            }
            isLoading = false
        }
        guard questionsListenerGeneration == generation else {
            seededHandle.cancel()
            return
        }
        seededQuestionsListener = seededHandle

        let featuredHandle = await listenerService.setupFeaturedHomeQuestionsListener { [weak self] result in
            guard let self, questionsListenerGeneration == generation else { return }
            switch result {
            case .success(let questions):
                featuredHomeQuestions = questions
                updatePublicQuestions()
            case .failure(let failure):
                logger.error("Featured home questions failed to load: \(failure.localizedDescription)")
            }
        }
        guard questionsListenerGeneration == generation else {
            featuredHandle.cancel()
            return
        }
        featuredHomeQuestionsListener = featuredHandle
    }

    private func setupTrioQuestionsListener() async {
        guard let listenerService else { return }
        trioListenerGeneration &+= 1
        let generation = trioListenerGeneration
        trioListener?.cancel()
        trioListener = nil

        let handle = await listenerService.setupTrioQuestionsListener { [weak self] result in
            guard let self, trioListenerGeneration == generation else { return }
            switch result {
            case .success(let questions):
                trioQuestions = filteredTrioQuestions(
                    questions,
                    selectedLanguageCode: AppLocalization.currentLanguageCode
                )
            case .failure(let failure):
                logger.error("Trio questions failed to load: \(failure.localizedDescription)")
            }
        }
        guard trioListenerGeneration == generation else {
            handle.cancel()
            return
        }
        trioListener = handle
    }

    private func updateGroupedQuestions() {
        groupedQuestions = Dictionary(grouping: questions, by: { $0.category })
        todaysQuestions = todaysQuestionSelector.select(from: questions)
    }

    private func updatePublicQuestions() {
        let merged = Dictionary(
            grouping: seededQuestions + featuredHomeQuestions,
            by: \.id
        )
        replaceQuestions(
            merged.compactMap { $0.value.first }
                .sorted { $0.createdAt > $1.createdAt }
        )
        updateGroupedQuestions()
    }

    private func upsertLocalQuestion(_ question: Question) {
        if let index = questionIndexByID[question.id] {
            questions[index] = question
        } else {
            var updatedQuestions = questions
            updatedQuestions.append(question)
            replaceQuestions(updatedQuestions)
        }

        if question.source == .userCreated &&
            question.moderationStatus == .approved &&
            question.isVisibleInTrio(selectedLanguageCode: AppLocalization.currentLanguageCode) {
            if let index = trioQuestions.firstIndex(where: { $0.id == question.id }) {
                trioQuestions[index] = question
            } else {
                trioQuestions.append(question)
            }
        } else {
            trioQuestions.removeAll { $0.id == question.id }
        }

        updateGroupedQuestions()
    }

    #if DEBUG
    func replaceTrioQuestionsForTesting(
        _ questions: [Question],
        selectedLanguageCode: String = AppLocalization.currentLanguageCode
    ) {
        trioQuestions = filteredTrioQuestions(questions, selectedLanguageCode: selectedLanguageCode)
    }

    func applyPublicQuestionListenerSnapshotForTesting(
        seededQuestions: [Question],
        featuredHomeQuestions: [Question] = []
    ) {
        self.seededQuestions = seededQuestions
        self.featuredHomeQuestions = featuredHomeQuestions
        updatePublicQuestions()
    }

    /// Puts the given handles where the Firestore listeners live, so a test can see `deinit`
    /// cancel them without a signed-in user or a live `QuestionService`.
    func installListenersForTesting(
        seeded: FirestoreListenerHandle,
        featuredHome: FirestoreListenerHandle,
        trio: FirestoreListenerHandle,
        userAnswers: FirestoreListenerHandle
    ) {
        seededQuestionsListener = seeded
        featuredHomeQuestionsListener = featuredHome
        trioListener = trio
        userAnswersListener = userAnswers
    }
    #endif

    private func filteredTrioQuestions(
        _ questions: [Question],
        selectedLanguageCode: String
    ) -> [Question] {
        questions.filter { $0.isVisibleInTrio(selectedLanguageCode: selectedLanguageCode) }
    }

    // MARK: - Public Methods

    var allQuestions: [Question] {
        questions.sorted { $0.createdAt > $1.createdAt }
    }

    /// Questions that the current user has answered at least one slot for,
    /// sorted by filled answer count descending.
    var mostAnsweredQuestions: [Question] {
        // Count filled slots once per question rather than inside the comparator, which recomputed
        // it for both operands on every comparison.
        questions
            .map { (question: $0, filledAnswerCount: filledAnswerCount(for: $0.id)) }
            .filter { $0.filledAnswerCount > 0 }
            .sorted { $0.filledAnswerCount > $1.filledAnswerCount }
            .map(\.question)
    }

    private func filledAnswerCount(for questionId: String) -> Int {
        guard let answers = currentUserAnswers[questionId]?.answers else { return 0 }
        return answers.reduce(into: 0) { count, answer in
            if !answer.isEmpty { count += 1 }
        }
    }

    /// Resolves question ids to questions in the order given, using the id index so a list of N
    /// entries costs N dictionary lookups instead of N scans over the corpus.
    func questions(withIDs questionIds: [String]) -> [Question] {
        questionIds.compactMap { question(withID: $0) }
    }

    func questions(for category: String) -> [Question] {
        return groupedQuestions[category] ?? []
    }

    /// Called once per entry when resolving a question list, so it must not allocate: the previous
    /// implementation concatenated all four caches into a new array on every call.
    func question(withID questionId: String) -> Question? {
        if let index = questionIndexByID[questionId] {
            return questions[index]
        }
        return trioQuestions.first { $0.id == questionId }
            ?? seededQuestions.first { $0.id == questionId }
            ?? featuredHomeQuestions.first { $0.id == questionId }
    }

    func fetchSharedQuestion(id questionId: String) async throws -> Question {
        guard let questionService else {
            if let question = question(withID: questionId), question.isShareable {
                return question
            }
            throw QuestionModelError.localModeUnsupported
        }

        let question = try await questionService.getShareableQuestion(id: questionId)
        upsertLocalQuestion(question)
        return question
    }

    /// Publishing a user-created question stays here, unlike the admin CRUD cluster AD-4 moved to
    /// `QuestionModerationStore`. `TrioPromptModel` is its caller — this is a user feature, and the
    /// audit's claim that every CRUD member was admin-only was wrong about this one.
    ///
    /// It writes nothing locally on purpose. The published question is `pending`, so neither listener
    /// query matches it and it has no place in the read model until a moderator approves it.
    func publishUserCreatedQuestion(text: String, category: String) async throws -> Question {
        guard let questionService else {
            let publishedQuestion = Question(
                id: UUID().uuidString,
                text: text,
                category: category,
                localizedTexts: [AppLocalization.currentLanguageCode: text],
                languageCode: AppLocalization.currentLanguageCode,
                source: .userCreated,
                createdAt: Date(),
                creatorUsername: nil,
                isAnnounced: false,
                moderationStatus: .pending,
                featuredPlacement: .none
            )
            return publishedQuestion
        }

        let publishedQuestion = try await questionService.publishUserCreatedQuestion(
            text: text,
            category: category
        )

        return publishedQuestion
    }

}

// MARK: - Answer-draft adapters

/// Lets `AnswerDraftStore` read and write the cached answer without owning it.
///
/// The cache stays here because this is where its readers and the Firestore listener that feeds it
/// already are, and because `currentUserAnswers` is `private(set)` — this file is the only place that
/// can write it. Deciding *when* to write is the store's job; knowing how to shape a `UserAnswer`,
/// resolve the user id and stamp the time is this type's.
extension QuestionModel: AnswerCaching {
    func currentAnswer(for questionId: String) -> UserAnswer? {
        currentUserAnswers[questionId]
    }

    func cache(_ answer: NormalizedAnswer, for questionId: String) {
        currentUserAnswers[questionId] = UserAnswer(
            questionId: questionId,
            userId: Auth.auth().currentUser?.uid
                ?? currentUserAnswers[questionId]?.userId
                ?? "local-user",
            answers: answer.texts,
            answeredAt: Date(),
            imageURLs: answer.urls,
            imageAttributions: answer.attributions
        )
    }

    func restore(_ previous: UserAnswer?, for questionId: String) {
        if let previous {
            currentUserAnswers[questionId] = previous
        } else {
            currentUserAnswers.removeValue(forKey: questionId)
        }
    }
}

/// Turns a typed save failure into the message the app already shows.
///
/// The copy is identical to what the editor set inline before; keeping localization here is what lets
/// the store stay free of `AppLocalization` and lets its tests assert on which failure occurred
/// rather than on translated text.
extension QuestionModel: AnswerSaveErrorReporting {
    func report(_ saveError: AnswerSaveError) {
        switch saveError {
        case .textSaveFailed:
            error = String(localized: "question.answer.saveError.text")

        case .imageURLSaveFailed:
            error = String(localized: "question.answer.saveError.imageURL")

        case let .imageUploadFailed(slotIndex, underlyingDescription):
            error = String(
                format: String(localized: "question.image.uploadError"),
                locale: AppLocalization.currentLocale,
                slotIndex + 1,
                underlyingDescription
            )
        }
    }
}
