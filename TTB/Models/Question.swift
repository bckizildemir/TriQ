import FirebaseAuth
import FirebaseFirestore
import Foundation

enum QuestionSource: String, Codable {
    case seeded
    case userCreated
}

enum QuestionModerationStatus: String, Codable, CaseIterable {
    case pending
    case approved
    case rejected
}

enum QuestionFeaturedPlacement: String, Codable, CaseIterable {
    case none
    case home
}

// Per-user answer stored in questions/{questionId}/userAnswers/{userId}.
struct UserAnswer {
    let questionId: String
    let userId: String
    let answers: [String]
    let answeredAt: Date
    // Optional image URLs per answer slot (nil = no image for that slot).
    let imageURLs: [String?]
    let imageAttributions: [AnswerImageAttribution?]

    init(
        questionId: String,
        userId: String,
        answers: [String],
        answeredAt: Date,
        imageURLs: [String?] = Array(repeating: nil, count: AnswerDraft.slotCount),
        imageAttributions: [AnswerImageAttribution?] = Array(repeating: nil, count: AnswerDraft.slotCount)
    ) {
        self.questionId = questionId
        self.userId = userId
        self.answers = answers
        self.answeredAt = answeredAt
        self.imageURLs = AnswerDraft.padded(imageURLs, with: nil)
        self.imageAttributions = AnswerDraft.padded(imageAttributions, with: nil)
    }
}

struct Question: Identifiable {
    let id: String
    let contentId: String
    let localizedTexts: [String: String]
    let languageCode: String?
    private let legacyText: String
    let category: String
    let source: QuestionSource
    var answers: [String]
    var isFavorite: Bool
    let createdAt: Date
    let createdBy: String?
    let creatorUsername: String?
    let isAnnounced: Bool
    let moderationStatus: QuestionModerationStatus
    let moderatedAt: Date?
    let moderatedBy: String?
    let rejectionReason: String?
    let featuredPlacement: QuestionFeaturedPlacement
    var lastAnsweredAt: Date?
    let announcedAt: Date?
    let announcedInReleaseId: String?

    // Respondent counters – updated transactionally on every saveAnswers call.
    var totalRespondents: Int
    var todayRespondents: Int
    var todayDate: String

    // Per-slot answer frequency map: "0" -> ["Mavi": 5, "Kırmızı": 3], ...
    var answerStats: [String: [String: Int]]

    var text: String {
        resolvedText(preferredLanguageCodes: AppLocalization.preferredLanguageCodes)
    }

    var fallbackText: String {
        legacyText
    }

    var isShareable: Bool {
        switch source {
        case .seeded:
            true
        case .userCreated:
            moderationStatus == .approved
        }
    }

    var shareURL: URL {
        URL(string: "https://ttbp-9d652.web.app/q/\(id)")!
    }

    func resolvedText(preferredLanguageCodes: [String]) -> String {
        AppLocalization.resolve(
            localizedTexts,
            legacy: legacyText,
            preferredLanguageCodes: preferredLanguageCodes
        )
    }

    init(
        id: String,
        text: String,
        category: String,
        contentId: String? = nil,
        localizedTexts: [String: String] = [:],
        languageCode: String? = nil,
        source: QuestionSource = .seeded,
        answers: [String] = [],
        isFavorite: Bool = false,
        createdAt: Date = Date(),
        createdBy: String? = nil,
        creatorUsername: String? = nil,
        isAnnounced: Bool = true,
        moderationStatus: QuestionModerationStatus = .approved,
        moderatedAt: Date? = nil,
        moderatedBy: String? = nil,
        rejectionReason: String? = nil,
        featuredPlacement: QuestionFeaturedPlacement = .none,
        lastAnsweredAt: Date? = nil,
        announcedAt: Date? = nil,
        announcedInReleaseId: String? = nil,
        totalRespondents: Int = 0,
        todayRespondents: Int = 0,
        todayDate: String = "",
        answerStats: [String: [String: Int]] = [:]
    ) {
        self.id = id
        legacyText = text
        self.localizedTexts = localizedTexts
        self.languageCode = languageCode
        self.category = category
        self.source = source
        self.answers = answers
        self.isFavorite = isFavorite
        self.createdAt = createdAt
        self.createdBy = createdBy
        self.creatorUsername = creatorUsername
        self.isAnnounced = isAnnounced
        self.moderationStatus = moderationStatus
        self.moderatedAt = moderatedAt
        self.moderatedBy = moderatedBy
        self.rejectionReason = rejectionReason
        self.featuredPlacement = featuredPlacement
        self.lastAnsweredAt = lastAnsweredAt
        self.announcedAt = announcedAt
        self.announcedInReleaseId = announcedInReleaseId
        self.totalRespondents = totalRespondents
        self.todayRespondents = todayRespondents
        self.todayDate = todayDate
        self.answerStats = answerStats
        self.contentId = contentId ?? Self.legacyContentID(category: category, text: text)
    }

    // Convert Firestore data to Question
    /// Signals that a Firestore field was present but could not be decoded, so the whole
    /// record must be rejected.
    private struct CorruptFieldError: Error {}

    /// Decodes a Firestore field that is optional in storage but must be valid when present.
    /// Returns the `default` when the key is absent and the decoded value when it decodes.
    /// Throws ``CorruptFieldError`` when the key is present but malformed, so the caller can
    /// reject the record. The return type is always a real value — absent and corrupt no
    /// longer share one optional.
    private static func requireValidIfPresent<T>(
        _ raw: Any?,
        default defaultValue: T,
        decode: (Any) -> T?
    ) throws -> T {
        guard let raw else { return defaultValue }
        guard let value = decode(raw) else { throw CorruptFieldError() }
        return value
    }

    static func fromFirestore(_ data: [String: Any], id: String) -> Question? {
        guard let text = data["text"] as? String,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let category = data["category"] as? String,
              !category.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return nil
        }

        // answers may be absent on freshly seeded questions
        let answers = data["answers"] as? [String] ?? []

        // source, isAnnounced, and moderationStatus are optional in storage but must be
        // valid when present; a present-but-malformed value means the record is corrupt.
        let source: QuestionSource
        let isAnnounced: Bool
        let moderationStatus: QuestionModerationStatus
        do {
            source = try requireValidIfPresent(
                data["source"],
                default: .seeded,
                decode: { ($0 as? String).flatMap(QuestionSource.init(rawValue:)) }
            )
            isAnnounced = try requireValidIfPresent(
                data["isAnnounced"],
                default: true,
                decode: { $0 as? Bool }
            )
            moderationStatus = try requireValidIfPresent(
                data["moderationStatus"],
                default: .approved,
                decode: { ($0 as? String).flatMap(QuestionModerationStatus.init(rawValue:)) }
            )
        } catch {
            return nil
        }

        let createdAt = (data["createdAt"] as? Timestamp)?.dateValue() ?? Date()
        let createdBy = data["createdBy"] as? String
        let creatorUsername = data["creatorUsername"] as? String
        let moderatedAt = (data["moderatedAt"] as? Timestamp)?.dateValue()
        let moderatedBy = data["moderatedBy"] as? String
        let rejectionReason = data["rejectionReason"] as? String
        let featuredPlacement = (data["featuredPlacement"] as? String).flatMap(QuestionFeaturedPlacement.init(rawValue:)) ?? .none
        let lastAnsweredAt = (data["lastAnsweredAt"] as? Timestamp)?.dateValue()
        let announcedAt = (data["announcedAt"] as? Timestamp)?.dateValue()
        let announcedInReleaseId = data["announcedInReleaseId"] as? String
        let favoriteUserIds = data["favoriteUserIds"] as? [String] ?? []
        let currentUserId = Auth.auth().currentUser?.uid
        let isFavorite = currentUserId != nil && favoriteUserIds.contains(currentUserId!)

        let totalRespondents = data["totalRespondents"] as? Int ?? 0
        let todayRespondents = data["todayRespondents"] as? Int ?? 0
        let todayDate = data["todayDate"] as? String ?? ""
        let localizedTexts = Self.localizedTextMap(from: data["localizedTexts"])
        let languageCode = (data["languageCode"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
        let contentId = (data["contentId"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty ?? Self.legacyContentID(category: category, text: text)

        // Firestore returns nested maps as [String: Any]; parse manually.
        var answerStats: [String: [String: Int]] = [:]
        if let rawStats = data["answerStats"] as? [String: Any] {
            for (slotKey, slotValue) in rawStats {
                if let slotMap = slotValue as? [String: Any] {
                    var typedMap: [String: Int] = [:]
                    for (answer, count) in slotMap {
                        if let intCount = count as? Int {
                            typedMap[answer] = intCount
                        }
                    }
                    answerStats[slotKey] = typedMap
                }
            }
        }

        return Question(
            id: id,
            text: text,
            category: category,
            contentId: contentId,
            localizedTexts: localizedTexts,
            languageCode: languageCode,
            source: source,
            answers: answers,
            isFavorite: isFavorite,
            createdAt: createdAt,
            createdBy: createdBy,
            creatorUsername: creatorUsername,
            isAnnounced: isAnnounced,
            moderationStatus: moderationStatus,
            moderatedAt: moderatedAt,
            moderatedBy: moderatedBy,
            rejectionReason: rejectionReason,
            featuredPlacement: featuredPlacement,
            lastAnsweredAt: lastAnsweredAt,
            announcedAt: announcedAt,
            announcedInReleaseId: announcedInReleaseId,
            totalRespondents: totalRespondents,
            todayRespondents: todayRespondents,
            todayDate: todayDate,
            answerStats: answerStats
        )
    }

    // Convert Question to Firestore data (admin add/update operations only).
    // answerStats, respondent counters, and per-user answers are intentionally
    // excluded here; they are managed exclusively through the transactional
    // saveAnswers path so that admin edits never reset crowdsourced data.
    func toFirestore() -> [String: Any] {
        var data: [String: Any] = [
            "text": fallbackText,
            "category": category,
            "contentId": contentId,
            "source": source.rawValue,
            "createdAt": createdAt,
            "createdBy": createdBy ?? NSNull(),
            "isAnnounced": isAnnounced,
            "moderationStatus": moderationStatus.rawValue,
            "featuredPlacement": featuredPlacement.rawValue,
        ]

        if let creatorUsername {
            data["creatorUsername"] = creatorUsername
        }

        if !localizedTexts.isEmpty {
            data["localizedTexts"] = localizedTexts
        }

        if let languageCode {
            data["languageCode"] = languageCode
        }

        if let lastAnsweredAt = lastAnsweredAt {
            data["lastAnsweredAt"] = Timestamp(date: lastAnsweredAt)
        }

        if let moderatedAt {
            data["moderatedAt"] = Timestamp(date: moderatedAt)
        }

        if let moderatedBy {
            data["moderatedBy"] = moderatedBy
        }

        if let rejectionReason {
            data["rejectionReason"] = rejectionReason
        }

        if let announcedAt = announcedAt {
            data["announcedAt"] = Timestamp(date: announcedAt)
        }

        if let announcedInReleaseId = announcedInReleaseId {
            data["announcedInReleaseId"] = announcedInReleaseId
        }

        return data
    }
}

// MARK: - Categories

extension Question {
    static let categories = Category.defaultCategories.map(\.id)
    static var answerPlaceholders: [String] {
        [
            String(localized: "question.answer.placeholder.1"),
            String(localized: "question.answer.placeholder.2"),
            String(localized: "question.answer.placeholder.3"),
        ]
    }

    static func localizedCategoryTitle(_ category: String) -> String {
        Category.fallbackTitle(for: category)
    }

    static func categoryIconName(_ category: String) -> String {
        Category.fallbackIcon(for: category)
    }
}

// MARK: - Computed Properties

extension Question {
    var isUserCreated: Bool {
        source == .userCreated
    }

    var isApprovedForPublicDisplay: Bool {
        source == .seeded || moderationStatus == .approved
    }

    var isFeaturedOnHome: Bool {
        source == .userCreated && moderationStatus == .approved && featuredPlacement == .home
    }

    var creatorAttributionUsername: String? {
        guard isUserCreated else { return nil }
        let trimmedUsername = creatorUsername?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmedUsername.isEmpty ? nil : trimmedUsername
    }

    var trioCreatedAtString: String {
        let calendar = Calendar.current
        let now = Date()

        if calendar.isDate(createdAt, equalTo: now, toGranularity: .day) {
            let minutes = max(0, calendar.dateComponents([.minute], from: createdAt, to: now).minute ?? 0)
            if minutes < 60 {
                return RelativeDateTimeFormatter().localizedString(fromTimeInterval: createdAt.timeIntervalSinceNow)
            }

            return RelativeDateTimeFormatter().localizedString(fromTimeInterval: createdAt.timeIntervalSinceNow)
        }

        let dayCount = calendar.dateComponents([.day], from: calendar.startOfDay(for: createdAt), to: calendar.startOfDay(for: now)).day ?? 0
        if dayCount > 0 && dayCount <= 6 {
            return RelativeDateTimeFormatter().localizedString(fromTimeInterval: createdAt.timeIntervalSinceNow)
        }

        return createdAt.formatted(
            Date.FormatStyle(date: .abbreviated, time: .omitted)
                .locale(AppLocalization.currentLocale)
        )
    }

    var answerTimeString: String {
        guard let lastAnsweredAt = lastAnsweredAt else { return "" }

        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: lastAnsweredAt, relativeTo: Date())
    }

    private static func localizedTextMap(from value: Any?) -> [String: String] {
        if let typed = value as? [String: String] {
            return typed
        }

        guard let raw = value as? [String: Any] else {
            return [:]
        }

        var parsed: [String: String] = [:]
        for (key, item) in raw {
            if let stringValue = item as? String {
                parsed[key] = stringValue
            }
        }
        return parsed
    }

    private static func legacyContentID(category: String, text: String) -> String {
        "legacy:\(category):\(text)"
    }

    func isVisibleInTrio(selectedLanguageCode: String) -> Bool {
        let selectedBaseCode = Self.baseLanguageCode(for: selectedLanguageCode)

        if let languageBaseCode = languageCode.map(Self.baseLanguageCode(for:)) {
            return languageBaseCode == selectedBaseCode
        }

        if !localizedTexts.isEmpty {
            return localizedTexts.keys.contains { Self.baseLanguageCode(for: $0) == selectedBaseCode }
        }

        if let inferredBaseCode = AppLocalization.languageCode(forText: fallbackText) {
            return inferredBaseCode == selectedBaseCode
        }

        return false
    }

    private static func baseLanguageCode(for languageCode: String) -> String {
        languageCode
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "-")
            .first
            .map(String.init) ?? languageCode
    }

    /// Returns the most common answer for a given slot index, or nil if no data.
    func topAnswer(for slot: Int) -> String? {
        let slotStats = answerStats["\(slot)"] ?? [:]
        guard !slotStats.isEmpty else { return nil }
        return slotStats.max(by: { $0.value < $1.value })?.key
    }

    func quickAnswerCandidates(
        limit: Int,
        excluding: [String] = [],
        preferredLanguageCode: String? = nil
    ) -> [String] {
        guard limit > 0, !answerStats.isEmpty else { return [] }

        let excludedKeys = Set(excluding.map(QuickAnswerSuggestionResolver.normalizedKey(for:)))
        let preferredBaseLanguageCode = preferredLanguageCode?.split(separator: "-").first.map(String.init)
        var aggregatedCounts: [String: Int] = [:]
        var displayValues: [String: String] = [:]

        for (_, slotAnswers) in answerStats {
            for (answer, count) in slotAnswers {
                let trimmed = answer.trimmingCharacters(in: .whitespacesAndNewlines)
                let key = QuickAnswerSuggestionResolver.normalizedKey(for: trimmed)
                let candidateLanguageCode = AppLocalization.languageCode(forText: trimmed)

                guard count > 0,
                      !trimmed.isEmpty,
                      !key.isEmpty,
                      !excludedKeys.contains(key),
                      preferredBaseLanguageCode == nil || candidateLanguageCode == nil || candidateLanguageCode == preferredBaseLanguageCode
                else {
                    continue
                }

                aggregatedCounts[key] = AnswerCounterCalculator.adding(
                    count,
                    to: aggregatedCounts[key, default: 0]
                )

                if let currentDisplayValue = displayValues[key] {
                    if Self.shouldPreferQuickAnswerDisplayValue(trimmed, over: currentDisplayValue) {
                        displayValues[key] = trimmed
                    }
                } else {
                    displayValues[key] = trimmed
                }
            }
        }

        return aggregatedCounts
            .sorted { lhs, rhs in
                if lhs.value == rhs.value {
                    let lhsDisplay = displayValues[lhs.key] ?? lhs.key
                    let rhsDisplay = displayValues[rhs.key] ?? rhs.key
                    return lhsDisplay.localizedStandardCompare(rhsDisplay) == .orderedAscending
                }

                return lhs.value > rhs.value
            }
            .compactMap { displayValues[$0.key] }
            .prefix(limit)
            .map { $0 }
    }

    private static func shouldPreferQuickAnswerDisplayValue(_ candidate: String, over current: String) -> Bool {
        if candidate.count != current.count {
            return candidate.count < current.count
        }

        let candidateRank = quickAnswerDisplayCasingRank(candidate)
        let currentRank = quickAnswerDisplayCasingRank(current)
        if candidateRank != currentRank {
            return candidateRank < currentRank
        }

        return candidate.localizedStandardCompare(current) == .orderedAscending
    }

    private static func quickAnswerDisplayCasingRank(_ value: String) -> Int {
        let hasUppercase = value.rangeOfCharacter(from: .uppercaseLetters) != nil
        let hasLowercase = value.rangeOfCharacter(from: .lowercaseLetters) != nil

        if hasUppercase && hasLowercase { return 0 }
        if hasLowercase { return 1 }
        if hasUppercase { return 2 }
        return 3
    }

    /// Preview-only data. Not used at runtime; real questions are seeded via Scripts/seed_questions.
    static let sampleQuestions = [
        // Daily Questions
        Question(id: UUID().uuidString, text: "Bugün seni en çok mutlu eden 3 şey neydi?", category: "Daily"),
        Question(id: UUID().uuidString, text: "Bugün yaptığın en keyifli 3 şey neydi?", category: "Daily"),
        Question(id: UUID().uuidString, text: "Bugün öğrendiğin en ilginç 3 şey neydi?", category: "Daily"),
        Question(id: UUID().uuidString, text: "Bugün en çok odaklandığın 3 şey neydi?", category: "Daily"),
        Question(id: UUID().uuidString, text: "Bugün yardım ettiğin 3 kişi ya da durum neydi?", category: "Daily"),
        Question(id: UUID().uuidString, text: "Bugün kendine ayırdığın en iyi 3 an neydi?", category: "Daily"),
        Question(id: UUID().uuidString, text: "Bugün seni en çok şaşırtan 3 şey neydi?", category: "Daily"),
        Question(id: UUID().uuidString, text: "Bugün aldığın en önemli 3 karar neydi?", category: "Daily"),

        // Personal Development
        Question(id: UUID().uuidString, text: "Hayatında en gurur duyduğun 3 başarın nedir?", category: "Personal"),
        Question(id: UUID().uuidString, text: "Kendini geliştirmek için yaptığın 3 şey nedir?", category: "Personal"),
        Question(id: UUID().uuidString, text: "Kendini 5 yıl içinde geliştirdiğin 3 alan ne olurdu?", category: "Personal"),
        Question(id: UUID().uuidString, text: "Bugün kendin için yaptığın 3 şey neydi?", category: "Personal"),
        Question(id: UUID().uuidString, text: "Son zamanlarda gelişim gösterdiğin 3 konu neydi?", category: "Personal"),
        Question(id: UUID().uuidString, text: "Geliştirmek istediğin 3 yönün nedir?", category: "Personal"),
        Question(id: UUID().uuidString, text: "Son okuduğun kitaptan aklında kalan 3 şey nedir?", category: "Personal"),
        Question(id: UUID().uuidString, text: "Kendinde en çok sevdiğin 3 özellik nedir?", category: "Personal"),

        // Relationships
        Question(id: UUID().uuidString, text: "İlişkilerinde seni mutlu eden 3 şey nedir?", category: "Relationships"),
        Question(id: UUID().uuidString, text: "Arkadaşlarınla yapmayı en çok sevdiğin 3 aktivite nedir?", category: "Relationships"),
        Question(id: UUID().uuidString, text: "Ailenle yaşadığın en güzel 3 anı neydi?", category: "Relationships"),
        Question(id: UUID().uuidString, text: "Bir arkadaşına verebileceğin en iyi 3 destek nedir?", category: "Relationships"),
        Question(id: UUID().uuidString, text: "İlişkilerinde en çok değer verdiğin 3 şey nedir?", category: "Relationships"),
        Question(id: UUID().uuidString, text: "Son zamanlarda daha çok vakit geçirmek istediğin 3 kişi kim?", category: "Relationships"),
        Question(id: UUID().uuidString, text: "İlişkilerinde seni en çok zorlayan 3 şey nedir?", category: "Relationships"),
        Question(id: UUID().uuidString, text: "Sevdiklerine ayırmak istediğin 3 özel zaman nedir?", category: "Relationships"),

        // Career
        Question(id: UUID().uuidString, text: "Kariyerinde ulaşmak istediğin 3 hedef nedir?", category: "Career"),
        Question(id: UUID().uuidString, text: "İşinde en sevdiğin 3 şey nedir?", category: "Career"),
        Question(id: UUID().uuidString, text: "Mesleğinde geliştirmek istediğin 3 beceri nedir?", category: "Career"),
        Question(id: UUID().uuidString, text: "Kariyerinde en gurur duyduğun 3 başarı nedir?", category: "Career"),
        Question(id: UUID().uuidString, text: "Kariyer hedeflerine ulaşmak için yaptığın 3 şey nedir?", category: "Career"),
        Question(id: UUID().uuidString, text: "İş-yaşam dengesini sağlamak için kullandığın 3 yöntem nedir?", category: "Career"),
        Question(id: UUID().uuidString, text: "İdeal iş ortamında bulunmasını istediğin 3 özellik nedir?", category: "Career"),
        Question(id: UUID().uuidString, text: "Kariyerinde değiştirmek istediğin 3 şey nedir?", category: "Career"),

        // Health
        Question(id: UUID().uuidString, text: "Bugün sağlığın için yaptığın 3 şey neydi?", category: "Health"),
        Question(id: UUID().uuidString, text: "Spor rutininin en sevdiğin 3 yönü nedir?", category: "Health"),
        Question(id: UUID().uuidString, text: "Uyku düzenini iyileştiren 3 alışkanlık nedir?", category: "Health"),
        Question(id: UUID().uuidString, text: "Beslenme alışkanlıklarını iyileştirmek için düşündüğün 3 adım nedir?", category: "Health"),
        Question(id: UUID().uuidString, text: "Stresle başa çıkmak için kullandığın 3 yöntem nedir?", category: "Health"),
        Question(id: UUID().uuidString, text: "Son zamanlarda edindiğin 3 sağlıklı alışkanlık nedir?", category: "Health"),
        Question(id: UUID().uuidString, text: "Mental sağlığını destekleyen 3 şey nedir?", category: "Health"),
        Question(id: UUID().uuidString, text: "Sağlığınla ilgili değiştirmek istediğin 3 şey nedir?", category: "Health"),

        // Goals
        Question(id: UUID().uuidString, text: "Bu yılki en önemli 3 hedefin nedir?", category: "Goals"),
        Question(id: UUID().uuidString, text: "Hedeflerine ulaşmak için bugün yaptığın 3 şey neydi?", category: "Goals"),
        Question(id: UUID().uuidString, text: "Kısa vadeli 3 hedefin nedir?", category: "Goals"),
        Question(id: UUID().uuidString, text: "Hayalini kurduğun bir şey için attığın 3 adım nedir?", category: "Goals"),
        Question(id: UUID().uuidString, text: "Seni motive eden 3 hedef nedir?", category: "Goals"),
        Question(id: UUID().uuidString, text: "Başarmak istediğin bir sonraki 3 büyük şey nedir?", category: "Goals"),
        Question(id: UUID().uuidString, text: "Hedeflerine ulaşmanı engelleyen 3 şey nedir?", category: "Goals"),
        Question(id: UUID().uuidString, text: "Hayatında değiştirmek istediğin 3 alışkanlık nedir?", category: "Goals"),

        // Creativity
        Question(id: UUID().uuidString, text: "Son zamanlarda yarattığın 3 şey nedir?", category: "Creativity"),
        Question(id: UUID().uuidString, text: "Yaratıcılığını geliştirmek için kullandığın 3 yöntem nedir?", category: "Creativity"),
        Question(id: UUID().uuidString, text: "Kendini en yaratıcı hissettiğin 3 an neydi?", category: "Creativity"),
        Question(id: UUID().uuidString, text: "İlgilendiğin 3 sanatsal aktivite nedir?", category: "Creativity"),
        Question(id: UUID().uuidString, text: "Yaratıcılığını tetikleyen 3 şey nedir?", category: "Creativity"),
        Question(id: UUID().uuidString, text: "Denemek istediğin 3 yeni hobi nedir?", category: "Creativity"),
        Question(id: UUID().uuidString, text: "Son ürettiğin 3 şey neydi?", category: "Creativity"),
        Question(id: UUID().uuidString, text: "Yaratıcı süreçte seni en çok zorlayan 3 şey nedir?", category: "Creativity"),
    ]
}

// MARK: - Moderation operations

/// The local copies an admin action produces, as three named operations rather than one generic
/// copier.
///
/// These replace `QuestionModel.copiedQuestion` and `moderatedQuestion` — a 27-line field-by-field
/// copy plus a `preserveRejectionReason: Bool` flag, which existed because a generic copier cannot
/// tell "leave this field alone" from "clear this field". Naming the three operations removes the
/// question: each one states every field it decides, so there is nothing to disambiguate.
///
/// Each operation mirrors the write its `QuestionService` counterpart performs. That pairing is the
/// point — the copy is what the admin list renders until a listener snapshot arrives, so a rule
/// encoded on one side only shows up as a row that looks wrong and then corrects itself.
extension Question {

    /// The result of a moderation decision, mirroring `QuestionService.updateQuestionModeration`.
    ///
    /// Two rules live here rather than at the call site, because the service applies them to every
    /// write regardless of who asked:
    ///
    /// - A reason belongs to a rejection. Any other status clears it.
    /// - Neither a rejected nor a pending question may hold a featured placement.
    func moderated(
        as status: QuestionModerationStatus,
        at moderatedAt: Date,
        by moderatorID: String?,
        rejectionReason: String? = nil
    ) -> Question {
        let resolvedReason: String? = status == .rejected
            ? rejectionReason?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            : nil

        let retainsPlacement = status == .approved

        return copy(
            text: fallbackText,
            category: category,
            localizedTexts: localizedTexts,
            languageCode: languageCode,
            moderationStatus: status,
            moderatedAt: moderatedAt,
            moderatedBy: moderatorID,
            rejectionReason: resolvedReason,
            featuredPlacement: retainsPlacement ? featuredPlacement : .none
        )
    }

    /// The result of a placement change, mirroring `QuestionService.updateQuestionFeaturedPlacement`,
    /// which writes that one field and nothing else.
    func featured(as placement: QuestionFeaturedPlacement) -> Question {
        copy(
            text: fallbackText,
            category: category,
            localizedTexts: localizedTexts,
            languageCode: languageCode,
            moderationStatus: moderationStatus,
            moderatedAt: moderatedAt,
            moderatedBy: moderatedBy,
            rejectionReason: rejectionReason,
            featuredPlacement: placement
        )
    }

    /// The result of an admin text edit, mirroring `QuestionService.updateQuestion`.
    ///
    /// `editingLanguageCode` is the language the admin is typing in. It becomes the question's own
    /// `languageCode` only when the question has none — a question decoded without one adopts the
    /// editor's locale, which is what the previous inline copy did.
    ///
    /// `contentId` is deliberately carried over rather than recomputed. It is derived from the
    /// original category and text, and `TodaysQuestionSelector` ranks by it, so recomputing here would
    /// silently move an edited question in the daily rotation.
    func edited(text: String, category: String, languageCode editingLanguageCode: String) -> Question {
        var updatedTexts = localizedTexts
        updatedTexts[editingLanguageCode] = text

        return copy(
            text: text,
            category: category,
            localizedTexts: updatedTexts,
            languageCode: languageCode ?? editingLanguageCode,
            moderationStatus: moderationStatus,
            moderatedAt: moderatedAt,
            moderatedBy: moderatedBy,
            rejectionReason: rejectionReason,
            featuredPlacement: featuredPlacement
        )
    }

    /// Private on purpose, and with no default arguments: the three operations above are the
    /// interface, and each must state every field it decides. A defaulted copier is what produced the
    /// `preserveRejectionReason` flag.
    private func copy(
        text: String,
        category: String,
        localizedTexts: [String: String],
        languageCode: String?,
        moderationStatus: QuestionModerationStatus,
        moderatedAt: Date?,
        moderatedBy: String?,
        rejectionReason: String?,
        featuredPlacement: QuestionFeaturedPlacement
    ) -> Question {
        Question(
            id: id,
            text: text,
            category: category,
            contentId: contentId,
            localizedTexts: localizedTexts,
            languageCode: languageCode,
            source: source,
            answers: answers,
            isFavorite: isFavorite,
            createdAt: createdAt,
            createdBy: createdBy,
            creatorUsername: creatorUsername,
            isAnnounced: isAnnounced,
            moderationStatus: moderationStatus,
            moderatedAt: moderatedAt,
            moderatedBy: moderatedBy,
            rejectionReason: rejectionReason,
            featuredPlacement: featuredPlacement,
            lastAnsweredAt: lastAnsweredAt,
            announcedAt: announcedAt,
            announcedInReleaseId: announcedInReleaseId,
            totalRespondents: totalRespondents,
            todayRespondents: todayRespondents,
            todayDate: todayDate,
            answerStats: answerStats
        )
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
