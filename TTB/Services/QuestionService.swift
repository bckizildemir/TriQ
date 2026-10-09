import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions
import Foundation
import os

enum MostAnsweredFilter {
    case daily
    case allTime
}

enum QuestionServiceError: LocalizedError {
    case unauthenticated
    case anonymousPublishingNotAllowed
    case invalidQuestionText

    var errorDescription: String? {
        switch self {
        case .unauthenticated:
            return String(localized: "question.error.notAuthenticated")
        case .anonymousPublishingNotAllowed:
            return String(localized: "question.error.mustCreateAccount")
        case .invalidQuestionText:
            return String(localized: "question.error.invalidText")
        }
    }
}

actor QuestionService {
    private let db = Firestore.firestore()
    private let functions = Functions.functions(region: "europe-west1")
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.ttb.app",
        category: "QuestionService")

    private struct BadgeDefinition: Decodable {
        let id: String
        let targetCount: Int
        let type: String
        let category: String?

        var badgeType: BadgeType {
            BadgeType(rawValue: type) ?? .total
        }
    }

    init() {
        let appName = db.app.name
        logger.debug("QuestionService initialized with Firestore app \(appName)")
    }

    func getAllQuestions() async throws -> [Question] {
        logger.debug("Fetching all questions for user \(Auth.auth().currentUser?.uid ?? "nil")")
        let snapshot = try await db.collection("questions").getDocuments()
        logger.debug("Fetched \(snapshot.documents.count) questions")
        return snapshot.documents.compactMap { document in
            Question.fromFirestore(document.data(), id: document.documentID)
        }
    }

    func getShareableQuestion(id questionId: String) async throws -> Question {
        let document = try await db.collection("questions").document(questionId).getDocument()
        guard let data = document.data(),
              let question = Question.fromFirestore(data, id: document.documentID),
              question.isShareable
        else {
            throw NSError(
                domain: "QuestionService",
                code: 404,
                userInfo: [NSLocalizedDescriptionKey: "Question not found."]
            )
        }

        return question
    }

    func addQuestion(_ question: Question) async throws {
        let docRef = db.collection("questions").document(question.id)
        try await docRef.setData(question.toFirestore())
    }

    func publishUserCreatedQuestion(text: String, category: String) async throws -> Question {
        guard let currentUser = Auth.auth().currentUser else {
            throw QuestionServiceError.unauthenticated
        }

        guard !currentUser.isAnonymous else {
            throw QuestionServiceError.anonymousPublishingNotAllowed
        }

        try await refreshIDToken(for: currentUser)

        let normalizedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedText.count >= 8 else {
            throw QuestionServiceError.invalidQuestionText
        }

        guard !category.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw QuestionServiceError.invalidQuestionText
        }

        let creatorUsername = try await currentUsername(for: currentUser.uid)

        let question = Question(
            id: UUID().uuidString,
            text: normalizedText,
            category: category,
            localizedTexts: [AppLocalization.currentLanguageCode: normalizedText],
            languageCode: AppLocalization.currentLanguageCode,
            source: .userCreated,
            answers: [],
            isFavorite: false,
            createdAt: Date(),
            createdBy: currentUser.uid,
            creatorUsername: creatorUsername,
            isAnnounced: false,
            moderationStatus: .pending,
            featuredPlacement: .none
        )

        try await addQuestion(question)
        return question
    }

    func updateQuestionModeration(
        questionId: String,
        status: QuestionModerationStatus,
        rejectionReason: String? = nil,
        moderatedBy: String
    ) async throws {
        var data: [String: Any] = [
            "moderationStatus": status.rawValue,
            "moderatedAt": FieldValue.serverTimestamp(),
            "moderatedBy": moderatedBy,
        ]

        if status == .rejected {
            let trimmedReason = rejectionReason?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !trimmedReason.isEmpty {
                data["rejectionReason"] = trimmedReason
            } else {
                data["rejectionReason"] = FieldValue.delete()
            }
            data["featuredPlacement"] = QuestionFeaturedPlacement.none.rawValue
        } else {
            data["rejectionReason"] = FieldValue.delete()
        }

        if status == .pending {
            data["featuredPlacement"] = QuestionFeaturedPlacement.none.rawValue
        }

        try await db.collection("questions").document(questionId).updateData(data)
    }

    func updateQuestionFeaturedPlacement(
        questionId: String,
        placement: QuestionFeaturedPlacement
    ) async throws {
        try await db.collection("questions").document(questionId).updateData([
            "featuredPlacement": placement.rawValue,
        ])
    }

    func updateQuestion(_ question: Question) async throws {
        let docRef = db.collection("questions").document(question.id)
        try await docRef.setData(question.toFirestore(), merge: true)
    }

    func deleteQuestion(_ questionId: String) async throws {
        let docRef = db.collection("questions").document(questionId)
        try await docRef.delete()
    }

    // MARK: - Save Answers (transactional)

    /// Saves the current user's answers (and optional image URLs) for a question in a single Firestore transaction.
    ///
    /// The transaction:
    /// 1. Reads the existing per-user subcollection document to determine previous answers.
    /// 2. Decrements old answer frequencies from `answerStats` when the user edits.
    /// 3. Increments new answer frequencies.
    /// 4. Updates `totalRespondents` (all-time unique users) and `todayRespondents` (today's unique users).
    /// 5. Writes the full answers array to the question document for backward compatibility.
    /// 6. Writes the per-user subcollection document.
    func saveAnswers(
        _ answers: [String],
        imageURLs: [String?] = [nil, nil, nil],
        imageAttributions: [AnswerImageAttribution?] = [nil, nil, nil],
        for questionId: String
    ) async throws {
        let urlsForFunctions: [String] = imageURLs.map { $0 ?? "" }
        let attributionsForFunctions: [[String: Any]] = imageAttributions.map { attribution in
            attribution?.firestoreValue ?? [:]
        }

        _ = try await functions.httpsCallable("saveQuestionAnswers").call([
            "questionId": questionId,
            "answers": answers,
            "imageURLs": urlsForFunctions,
            "imageAttributions": attributionsForFunctions,
        ])
    }

    // MARK: - Ranked Most-Answered Queries

    /// Fetches the top questions ranked by respondent count.
    /// - `.allTime`: sorted by `totalRespondents` descending.
    /// - `.daily`: only questions answered today, sorted by `todayRespondents` descending.
    func fetchMostAnsweredQuestions(filter: MostAnsweredFilter, limit: Int = 20) async throws -> [Question] {
        let seededSnapshot: QuerySnapshot
        let userCreatedSnapshot: QuerySnapshot

        switch filter {
        case .allTime:
            seededSnapshot = try await db.collection("questions")
                .whereField("source", isEqualTo: QuestionSource.seeded.rawValue)
                .whereField("totalRespondents", isGreaterThan: 0)
                .order(by: "totalRespondents", descending: true)
                .limit(to: limit)
                .getDocuments()
            userCreatedSnapshot = try await db.collection("questions")
                .whereField("source", isEqualTo: QuestionSource.userCreated.rawValue)
                .whereField("moderationStatus", isEqualTo: QuestionModerationStatus.approved.rawValue)
                .whereField("totalRespondents", isGreaterThan: 0)
                .order(by: "totalRespondents", descending: true)
                .limit(to: limit)
                .getDocuments()

        case .daily:
            let today = Self.todayDateString()
            seededSnapshot = try await db.collection("questions")
                .whereField("source", isEqualTo: QuestionSource.seeded.rawValue)
                .whereField("todayDate", isEqualTo: today)
                .order(by: "todayRespondents", descending: true)
                .limit(to: limit)
                .getDocuments()
            userCreatedSnapshot = try await db.collection("questions")
                .whereField("source", isEqualTo: QuestionSource.userCreated.rawValue)
                .whereField("moderationStatus", isEqualTo: QuestionModerationStatus.approved.rawValue)
                .whereField("todayDate", isEqualTo: today)
                .order(by: "todayRespondents", descending: true)
                .limit(to: limit)
                .getDocuments()
        }

        let questions = (seededSnapshot.documents + userCreatedSnapshot.documents)
            .compactMap { Question.fromFirestore($0.data(), id: $0.documentID) }

        switch filter {
        case .allTime:
            return Array(questions.sorted { $0.totalRespondents > $1.totalRespondents }.prefix(limit))
        case .daily:
            return Array(questions.sorted { $0.todayRespondents > $1.todayRespondents }.prefix(limit))
        }
    }

    func deleteAnswerForAccountDeletion(questionId: String, userId: String) async throws {
        let questionRef = db.collection("questions").document(questionId)
        let userAnswerRef = questionRef.collection("userAnswers").document(userId)

        let replacementLastAnsweredAt = try await latestRemainingAnsweredAt(
            questionRef: questionRef,
            excludingUserId: userId
        )

        _ = try await db.runTransaction { transaction, errorPointer in
            let questionSnapshot: DocumentSnapshot
            let userAnswerSnapshot: DocumentSnapshot

            do {
                questionSnapshot = try transaction.getDocument(questionRef)
                userAnswerSnapshot = try transaction.getDocument(userAnswerRef)
            } catch let error as NSError {
                errorPointer?.pointee = error
                return nil
            }

            guard userAnswerSnapshot.exists else {
                return nil
            }

            if !questionSnapshot.exists {
                transaction.deleteDocument(userAnswerRef)
                return nil
            }

            let questionData = questionSnapshot.data() ?? [:]
            let userAnswerData = userAnswerSnapshot.data() ?? [:]
            let answers = userAnswerData["answers"] as? [String] ?? []
            let answeredAt = (userAnswerData["answeredAt"] as? Timestamp)?.dateValue() ?? .now

            let currentState = QuestionAnswerAggregateState(
                answerStats: Self.answerStats(from: questionData["answerStats"]),
                totalRespondents: questionData["totalRespondents"] as? Int ?? 0,
                todayRespondents: questionData["todayRespondents"] as? Int ?? 0,
                todayDate: questionData["todayDate"] as? String ?? "",
                lastAnsweredAt: (questionData["lastAnsweredAt"] as? Timestamp)?.dateValue()
            )

            let updatedState = QuestionAnswerDeletionReducer.apply(
                to: currentState,
                removingAnswers: answers,
                answeredAt: answeredAt,
                replacementLastAnsweredAt: replacementLastAnsweredAt
            )

            var questionUpdates: [String: Any] = [
                "answerStats": Self.answerStatsForFirestore(updatedState.answerStats),
                "totalRespondents": updatedState.totalRespondents,
                "todayRespondents": updatedState.todayRespondents,
                "todayDate": updatedState.todayDate,
            ]

            if let lastAnsweredAt = updatedState.lastAnsweredAt {
                questionUpdates["lastAnsweredAt"] = Timestamp(date: lastAnsweredAt)
            } else {
                questionUpdates["lastAnsweredAt"] = FieldValue.delete()
            }

            transaction.updateData(questionUpdates, forDocument: questionRef)
            transaction.deleteDocument(userAnswerRef)
            return nil
        }
    }

    func backfillBadgeProgressIfNeeded() async {
        guard let currentUser = Auth.auth().currentUser, !currentUser.isAnonymous else { return }
        let userId = currentUser.uid

        let userRef = db.collection("users").document(userId)

        do {
            let userSnapshot = try await userRef.getDocument()
            let userData = userSnapshot.data() ?? [:]
            let storedTotal = userData["totalAnswered"] as? Int
                ?? userData["totalAnswers"] as? Int
                ?? 0
            let storedCompletedQuestions = userData["completedQuestionIds"] as? [String] ?? []
            let storedProgress = Self.doubleMap(from: userData["badgeProgress"])
            let needsBackfill = storedTotal == 0
                || storedCompletedQuestions.isEmpty
                || storedProgress.isEmpty

            guard needsBackfill else { return }

            let answersSnapshot = try await db.collectionGroup("userAnswers")
                .whereField("userId", isEqualTo: userId)
                .getDocuments()

            let completedAnswers: [(questionId: String, answeredAt: Date)] = answersSnapshot.documents.compactMap { document in
                let questionId = document.reference.parent.parent?.documentID ?? ""
                let answers = document.data()["answers"] as? [String] ?? []
                guard !questionId.isEmpty, answers.filter({ !$0.isEmpty }).count == 3 else {
                    return nil
                }
                let answeredAt = (document.data()["answeredAt"] as? Timestamp)?.dateValue() ?? Date()
                return (questionId: questionId, answeredAt: answeredAt)
            }

            guard !completedAnswers.isEmpty else { return }

            let questionsSnapshot = try await db.collection("questions").getDocuments()
            let categoriesByQuestionId: [String: String] = questionsSnapshot.documents.reduce(into: [:]) { result, document in
                result[document.documentID] = document.data()["category"] as? String ?? ""
            }

            var categoryAnswers: [String: Int] = [:]
            for completedAnswer in completedAnswers {
                let category = categoriesByQuestionId[completedAnswer.questionId] ?? ""
                guard !category.isEmpty else { continue }
                categoryAnswers[category] = (categoryAnswers[category] ?? 0) + 1
            }

            let totalAnswered = completedAnswers.count
            let dailyAnswers = completedAnswers.filter { Calendar.current.isDateInToday($0.answeredAt) }.count
            let weeklyAnswers = completedAnswers.filter {
                guard let sevenDaysAgo = Calendar.current.date(byAdding: .day, value: -6, to: Date()) else {
                    return false
                }
                return $0.answeredAt >= Calendar.current.startOfDay(for: sevenDaysAgo)
            }.count
            let lastAnsweredDate = completedAnswers.map(\.answeredAt).max()
            let currentStreak = AnswerStreakCalculator.currentStreak(
                from: completedAnswers.map(\.answeredAt),
                calendar: .current
            )
            let badgeDefinitions = await fetchBadgeDefinitions()

            var badgeProgress: [String: Double] = [:]
            var unlockedBadges: [String] = []
            for badgeDefinition in badgeDefinitions {
                let progress = Self.progress(
                    for: badgeDefinition,
                    totalAnswered: totalAnswered,
                    categoryAnswers: categoryAnswers,
                    currentStreak: currentStreak
                )
                badgeProgress[badgeDefinition.id] = progress
                if progress >= 1.0 {
                    unlockedBadges.append(badgeDefinition.id)
                }
            }

            var updates: [String: Any] = [
                "totalAnswered": totalAnswered,
                "dailyAnswers": dailyAnswers,
                "weeklyAnswers": weeklyAnswers,
                "completedQuestionIds": completedAnswers.map(\.questionId),
                "categoryAnswers": categoryAnswers,
                "currentStreak": currentStreak,
            ]
            if let lastAnsweredDate {
                updates["lastAnsweredDate"] = Timestamp(date: lastAnsweredDate)
            }
            if !badgeProgress.isEmpty {
                updates["badgeProgress"] = badgeProgress
                updates["unlockedBadges"] = unlockedBadges
            }

            try await userRef.setData(updates, merge: true)
        } catch {
            logger.error("Badge backfill error: \(error.localizedDescription)")
        }
    }

    // MARK: - Listeners
    //
    // Each listener fetches `Firestore` in the method instead of reading `db`. A registration built
    // from the stored `db` joins this actor's region and cannot be sent into the `Sendable`
    // `FirestoreListenerHandle`; one built from a fresh `Firestore` can. Each Firebase closure only
    // forwards raw values to a `deliver…` function, which a test runs without Firebase.

    /// Listens in real time to all answers the current user has saved across all questions.
    /// Uses a collection group query on `userAnswers` filtered by the `userId` field.
    /// Returns nil, and delivers an empty dictionary, when no user is signed in.
    func setupUserAnswersListener(
        completion: @escaping @MainActor @Sendable ([String: UserAnswer]) -> Void
    ) -> FirestoreListenerHandle? {
        guard let userId = Auth.auth().currentUser?.uid else {
            Task { @MainActor in completion([:]) }
            return nil
        }

        let logger = logger
        let registration = Firestore.firestore().collectionGroup("userAnswers")
            .whereField("userId", isEqualTo: userId)
            .addSnapshotListener { snapshot, error in
                Self.deliverUserAnswers(
                    documents: snapshot?.documents.map { (path: $0.reference.path, data: $0.data()) },
                    error: error,
                    userId: userId,
                    logger: logger,
                    to: completion
                )
            }
        return FirestoreListenerHandle(registration: registration)
    }

    func setupSeededQuestionsListener(
        completion: @escaping @MainActor @Sendable ([Question]) -> Void
    ) -> FirestoreListenerHandle {
        logger.debug("Setting up seeded questions listener")
        let logger = logger
        let registration = Firestore.firestore().collection("questions")
            .whereField("source", isEqualTo: QuestionSource.seeded.rawValue)
            .addSnapshotListener { snapshot, error in
                Self.deliverQuestions(
                    documents: snapshot?.documents.map { (id: $0.documentID, data: $0.data()) },
                    error: error,
                    feed: "Seeded questions",
                    logger: logger,
                    to: completion
                )
            }
        return FirestoreListenerHandle(registration: registration)
    }

    func setupFeaturedHomeQuestionsListener(
        completion: @escaping @MainActor @Sendable ([Question]) -> Void
    ) -> FirestoreListenerHandle {
        logger.debug("Setting up featured home questions listener")
        let logger = logger
        let registration = Firestore.firestore().collection("questions")
            .whereField("source", isEqualTo: QuestionSource.userCreated.rawValue)
            .whereField("moderationStatus", isEqualTo: QuestionModerationStatus.approved.rawValue)
            .whereField("featuredPlacement", isEqualTo: QuestionFeaturedPlacement.home.rawValue)
            .order(by: "createdAt", descending: true)
            .addSnapshotListener { snapshot, error in
                Self.deliverQuestions(
                    documents: snapshot?.documents.map { (id: $0.documentID, data: $0.data()) },
                    error: error,
                    feed: "Featured home",
                    logger: logger,
                    to: completion
                )
            }
        return FirestoreListenerHandle(registration: registration)
    }

    func setupTrioQuestionsListener(
        completion: @escaping @MainActor @Sendable ([Question]) -> Void
    ) -> FirestoreListenerHandle {
        logger.debug("Setting up Trio questions listener")
        let logger = logger
        let registration = Firestore.firestore().collection("questions")
            .whereField("source", isEqualTo: QuestionSource.userCreated.rawValue)
            .whereField("moderationStatus", isEqualTo: QuestionModerationStatus.approved.rawValue)
            .order(by: "createdAt", descending: true)
            .addSnapshotListener { snapshot, error in
                Self.deliverQuestions(
                    documents: snapshot?.documents.map { (id: $0.documentID, data: $0.data()) },
                    error: error,
                    feed: "Trio",
                    logger: logger,
                    to: completion
                )
            }
        return FirestoreListenerHandle(registration: registration)
    }

    /// Delivers one question-feed snapshot callback on the main actor, when it maps to questions.
    static func deliverQuestions(
        documents: [(id: String, data: [String: Any])]?,
        error: Error?,
        feed: String,
        logger: Logger,
        to completion: @escaping @MainActor @Sendable ([Question]) -> Void
    ) {
        guard let questions = questions(fromSnapshot: documents, error: error, feed: feed, logger: logger) else {
            return
        }
        Task { @MainActor in completion(questions) }
    }

    /// Maps one question-feed snapshot callback to questions. Documents that do not decode are
    /// dropped. A listener error, or a snapshot with no documents, is logged and maps to nil, so
    /// the feed keeps what it last showed.
    static func questions(
        fromSnapshot documents: [(id: String, data: [String: Any])]?,
        error: Error?,
        feed: String,
        logger: Logger
    ) -> [Question]? {
        if let error {
            logger.error("\(feed, privacy: .public) listener error: \(error.localizedDescription)")
            return nil
        }

        guard let documents else {
            logger.error("No \(feed, privacy: .public) documents received from Firestore")
            return nil
        }

        let questions = documents.compactMap { document in
            Question.fromFirestore(document.data, id: document.id)
        }
        logger.debug("\(feed, privacy: .public) listener parsed \(questions.count) of \(documents.count) documents")
        return questions
    }

    /// Delivers one `userAnswers` snapshot callback on the main actor, when it maps to answers.
    static func deliverUserAnswers(
        documents: [(path: String, data: [String: Any])]?,
        error: Error?,
        userId: String,
        logger: Logger,
        to completion: @escaping @MainActor @Sendable ([String: UserAnswer]) -> Void
    ) {
        guard let answers = userAnswers(fromSnapshot: documents, error: error, userId: userId, logger: logger) else {
            return
        }
        Task { @MainActor in completion(answers) }
    }

    /// Maps one `userAnswers` snapshot callback to the user's answers keyed by question id. A
    /// listener error is logged and maps to nil; a snapshot with no documents maps to no answers.
    /// A document whose path names no question is dropped.
    static func userAnswers(
        fromSnapshot documents: [(path: String, data: [String: Any])]?,
        error: Error?,
        userId: String,
        logger: Logger
    ) -> [String: UserAnswer]? {
        if let error {
            logger.error("userAnswers listener error: \(error.localizedDescription)")
            return nil
        }

        var answersByQuestionID: [String: UserAnswer] = [:]
        for document in documents ?? [] {
            guard let questionId = questionID(fromUserAnswerPath: document.path) else { continue }
            let data = document.data
            let rawURLs = data["imageURLs"] as? [String] ?? []
            answersByQuestionID[questionId] = UserAnswer(
                questionId: questionId,
                userId: userId,
                answers: data["answers"] as? [String] ?? [],
                answeredAt: (data["answeredAt"] as? Timestamp)?.dateValue() ?? Date(),
                imageURLs: rawURLs.map { $0.isEmpty ? nil : $0 },
                imageAttributions: imageAttributions(from: data["imageAttributions"])
            )
        }
        return answersByQuestionID
    }

    /// The id of the question that owns a `userAnswers` document: the document two levels up, as
    /// in `questions/{questionId}/userAnswers/{userId}`. Nil for a path with no such document.
    static func questionID(fromUserAnswerPath path: String) -> String? {
        let components = path.split(separator: "/")
        guard components.count >= 4 else { return nil }
        return String(components[components.count - 3])
    }

    // MARK: - Helpers

    private func refreshIDToken(for user: User) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            user.getIDTokenForcingRefresh(true) { _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    static func todayDateString() -> String {
        dateString(for: .now)
    }

    static func dateString(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }

    private func fetchBadgeDefinitions() async -> [BadgeDefinition] {
        if let snapshot = try? await db.collection("badges").getDocuments() {
            let remoteDefinitions = snapshot.documents.compactMap { document -> BadgeDefinition? in
                let data = document.data()
                return BadgeDefinition(
                    id: document.documentID,
                    targetCount: data["targetCount"] as? Int ?? 0,
                    type: data["type"] as? String ?? "total",
                    category: data["category"] as? String
                )
            }
            if !remoteDefinitions.isEmpty {
                return remoteDefinitions
            }
        }

        guard let url = Bundle.main.url(forResource: "BadgeDefinitions", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let bundledDefinitions = try? JSONDecoder().decode([BadgeDefinition].self, from: data)
        else {
            return []
        }
        return bundledDefinitions
    }

    private func currentUsername(for userId: String) async throws -> String? {
        let snapshot = try await db.collection("users").document(userId).getDocument()
        let username = (snapshot.data()?["username"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return username?.isEmpty == false ? username : nil
    }

    private static func intMap(from value: Any?) -> [String: Int] {
        if let typed = value as? [String: Int] {
            return typed
        }
        guard let raw = value as? [String: Any] else {
            return [:]
        }

        var parsed: [String: Int] = [:]
        for (key, value) in raw {
            if let intValue = value as? Int {
                parsed[key] = intValue
            } else if let number = value as? NSNumber {
                parsed[key] = number.intValue
            }
        }
        return parsed
    }

    private static func answerStats(from value: Any?) -> [String: [String: Int]] {
        guard let rawStats = value as? [String: Any] else {
            return [:]
        }

        var parsed: [String: [String: Int]] = [:]
        for (slotKey, slotValue) in rawStats {
            if let slotMap = slotValue as? [String: Any] {
                parsed[slotKey] = intMap(from: slotMap)
            }
        }
        return parsed
    }

    private static func answerStatsForFirestore(_ answerStats: [String: [String: Int]]) -> [String: Any] {
        answerStats.reduce(into: [String: Any]()) { partialResult, entry in
            partialResult[entry.key] = entry.value as [String: Any]
        }
    }

    private static func imageAttributions(from value: Any?) -> [AnswerImageAttribution?] {
        guard let rawValues = value as? [Any] else {
            return [nil, nil, nil]
        }

        var parsed = rawValues.map { AnswerImageAttribution(firestoreValue: $0) }
        while parsed.count < 3 {
            parsed.append(nil)
        }
        return Array(parsed.prefix(3))
    }

    private static func doubleMap(from value: Any?) -> [String: Double] {
        if let typed = value as? [String: Double] {
            return typed
        }
        guard let raw = value as? [String: Any] else {
            return [:]
        }

        var parsed: [String: Double] = [:]
        for (key, value) in raw {
            if let doubleValue = value as? Double {
                parsed[key] = doubleValue
            } else if let intValue = value as? Int {
                parsed[key] = Double(intValue)
            } else if let number = value as? NSNumber {
                parsed[key] = number.doubleValue
            }
        }
        return parsed
    }

    private func latestRemainingAnsweredAt(
        questionRef: DocumentReference,
        excludingUserId userId: String
    ) async throws -> Date? {
        let snapshot = try await questionRef.collection("userAnswers")
            .order(by: "answeredAt", descending: true)
            .limit(to: 2)
            .getDocuments()

        for document in snapshot.documents where document.documentID != userId {
            if let answeredAt = (document.data()["answeredAt"] as? Timestamp)?.dateValue() {
                return answeredAt
            }
        }

        return nil
    }

    private static func progress(
        for badge: BadgeDefinition,
        totalAnswered: Int,
        categoryAnswers: [String: Int],
        currentStreak: Int
    ) -> Double {
        guard badge.targetCount > 0 else {
            return 0.0
        }

        switch badge.badgeType {
        case .total:
            return BadgeProgressCalculator.progress(
                currentCount: totalAnswered,
                targetCount: badge.targetCount
            )
        case .category:
            guard let category = badge.category else {
                return 0.0
            }
            return BadgeProgressCalculator.progress(
                currentCount: categoryAnswers[category] ?? 0,
                targetCount: badge.targetCount
            )
        case .streak:
            return BadgeProgressCalculator.progress(
                currentCount: currentStreak,
                targetCount: badge.targetCount
            )
        }
    }
}

// MARK: - QuestionModerating

/// The live adapter at the moderation seam. Method-for-method with this actor's own surface; the
/// renaming exists so the protocol reads as a capability rather than as this actor's history, which is
/// the same reason `FavoriteService`'s adapter renames.
extension QuestionService: QuestionModerating {
    func allQuestions() async throws -> [Question] {
        try await getAllQuestions()
    }

    func add(_ question: Question) async throws {
        try await addQuestion(question)
    }

    func update(_ question: Question) async throws {
        try await updateQuestion(question)
    }

    func delete(id questionId: String) async throws {
        try await deleteQuestion(questionId)
    }

    /// The empty-string fallback is confined to this adapter on purpose.
    ///
    /// `updateQuestionModeration` writes whatever it is given, so an unknown moderator becomes `""` in
    /// Firestore while `Question.moderated` keeps it `nil` locally. That divergence is pre-existing and
    /// unreachable in practice — `AdminAccessGuardView` requires a loaded admin profile, so there is
    /// always a signed-in user — and changing what the field holds is a Firestore-shape decision, not
    /// this seam's. Keeping the `??` here means the store and the local copy deal only in the optional.
    func updateModeration(
        questionId: String,
        status: QuestionModerationStatus,
        rejectionReason: String?,
        moderatedBy: String?
    ) async throws {
        try await updateQuestionModeration(
            questionId: questionId,
            status: status,
            rejectionReason: rejectionReason,
            moderatedBy: moderatedBy ?? ""
        )
    }

    func updateFeaturedPlacement(
        questionId: String,
        placement: QuestionFeaturedPlacement
    ) async throws {
        try await updateQuestionFeaturedPlacement(questionId: questionId, placement: placement)
    }
}
