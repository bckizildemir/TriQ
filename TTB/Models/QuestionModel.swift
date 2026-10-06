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
    private let todaysQuestionSelector: TodaysQuestionSelector
    private var seededQuestionsListener: ListenerRegistration?
    private var featuredHomeQuestionsListener: ListenerRegistration?
    private var trioListener: ListenerRegistration?
    private var userAnswersListener: ListenerRegistration?
    private var authStateHandle: AuthStateDidChangeListenerHandle?
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
        self.todaysQuestionSelector = todaysQuestionSelector
        replaceQuestions(localQuestions)
        currentUserAnswers = localUserAnswers
        updateGroupedQuestions()
    }

    /// `isolated` so the cleanup can read the main-actor listener handles. Below iOS 18.4 the
    /// compiler links a main-actor back-deploy shim, so this needs no deployment-target change.
    isolated deinit {
        seededQuestionsListener?.remove()
        featuredHomeQuestionsListener?.remove()
        trioListener?.remove()
        userAnswersListener?.remove()
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
                    self.logger.debug("Setting up question listeners")
                    await self.setupQuestionsListener()
                    await self.setupTrioQuestionsListener()
                    await self.setupUserAnswersListener()
                } else {
                    self.clearRemoteState()
                }
            }
        }
    }

    private func clearRemoteState() {
        seededQuestionsListener?.remove()
        seededQuestionsListener = nil
        featuredHomeQuestionsListener?.remove()
        featuredHomeQuestionsListener = nil
        trioListener?.remove()
        trioListener = nil
        userAnswersListener?.remove()
        userAnswersListener = nil
        replaceQuestions([])
        seededQuestions = []
        featuredHomeQuestions = []
        groupedQuestions = [:]
        todaysQuestions = []
        trioQuestions = []
        currentUserAnswers = [:]
        isLoading = false
    }

    private func setupUserAnswersListener() async {
        guard let questionService else { return }
        userAnswersListener?.remove()
        userAnswersListener = await questionService.setupUserAnswersListener { [weak self] answers in
            Task { @MainActor in
                self?.currentUserAnswers = answers
            }
        }
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
        guard questionService != nil else {
            updateGroupedQuestions()
            return
        }
        await setupQuestionsListener()
        await setupTrioQuestionsListener()
    }

    private func setupQuestionsListener() async {
        guard let questionService else { return }
        isLoading = true
        seededQuestionsListener?.remove()
        featuredHomeQuestionsListener?.remove()

        seededQuestionsListener = await questionService.setupSeededQuestionsListener { [weak self] questions in
            Task { @MainActor in
                guard let self = self else { return }
                self.seededQuestions = questions
                self.updatePublicQuestions()
                self.isLoading = false
            }
        }

        featuredHomeQuestionsListener = await questionService.setupFeaturedHomeQuestionsListener { [weak self] questions in
            Task { @MainActor in
                guard let self = self else { return }
                self.featuredHomeQuestions = questions
                self.updatePublicQuestions()
            }
        }
    }

    private func setupTrioQuestionsListener() async {
        guard let questionService else { return }
        trioListener?.remove()

        trioListener = await questionService.setupTrioQuestionsListener { [weak self] questions in
            Task { @MainActor in
                guard let self = self else { return }
                self.trioQuestions = self.filteredTrioQuestions(
                    questions,
                    selectedLanguageCode: AppLocalization.currentLanguageCode
                )
            }
        }
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

    /// Puts the given registrations where the Firestore listeners live, so a test can see `deinit`
    /// remove them without a signed-in user or a live `QuestionService`.
    func installListenersForTesting(
        seeded: any ListenerRegistration,
        featuredHome: any ListenerRegistration,
        trio: any ListenerRegistration,
        userAnswers: any ListenerRegistration
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
