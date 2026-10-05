import CoreFoundation
import FirebaseFirestore
import Foundation

enum QuestionListShareStatus: String {
    case active
    case revoked
    case accepted
    case left
    case unknown
}

enum SharedQuestionListCardMode: Equatable {
    case answerCard
    case comparison
}

struct QuestionListShare: Identifiable, Equatable {
    static let defaultRecipientCap = 25

    let id: String
    let ownerId: String
    let ownerDisplayName: String
    let sourceListId: String
    let listName: String
    let questionIds: [String]
    let includeOwnerAnswers: Bool
    let ownerAnswerSnapshots: [String: [String]]
    let shareCode: String?
    let recipientCap: Int
    let acceptedRecipientCount: Int
    let status: QuestionListShareStatus
    let isLinkEnabled: Bool
    let createdAt: Date
    let updatedAt: Date

    var isActive: Bool {
        status == .active
    }

    var acceptsNewRecipients: Bool {
        isActive
            && isLinkEnabled
            && recipientCap > 0
            && acceptedRecipientCount >= 0
            && acceptedRecipientCount < recipientCap
    }

    var shareURL: URL? {
        guard let shareCode, !shareCode.isEmpty else { return nil }
        return Self.shareURL(for: shareCode)
    }

    static func shareURL(for shareCode: String) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "ttbp-9d652.web.app"
        components.path = "/share/lists/\(shareCode)"
        return components.url
    }

    /// Also stamps `updatedAt` with the current date, regardless of which fields change.
    func updated(
        shareCode: String? = nil,
        status: QuestionListShareStatus? = nil,
        isLinkEnabled: Bool? = nil
    ) -> QuestionListShare {
        QuestionListShare(
            id: id,
            ownerId: ownerId,
            ownerDisplayName: ownerDisplayName,
            sourceListId: sourceListId,
            listName: listName,
            questionIds: questionIds,
            includeOwnerAnswers: includeOwnerAnswers,
            ownerAnswerSnapshots: ownerAnswerSnapshots,
            shareCode: shareCode ?? self.shareCode,
            recipientCap: recipientCap,
            acceptedRecipientCount: acceptedRecipientCount,
            status: status ?? self.status,
            isLinkEnabled: isLinkEnabled ?? self.isLinkEnabled,
            createdAt: createdAt,
            updatedAt: Date()
        )
    }

    func ownerTextSnapshot(for questionId: String) -> [String] {
        ownerAnswerSnapshots[questionId] ?? []
    }

    func recipientCardMode(for questionId: String) -> SharedQuestionListCardMode {
        ownerTextSnapshot(for: questionId).contains { !$0.isEmpty } ? .comparison : .answerCard
    }

    static func fromFirestore(_ data: [String: Any], id: String) -> QuestionListShare? {
        guard let ownerId = data["ownerId"] as? String else {
            return nil
        }

        let ownerDisplayName = data["ownerDisplayName"] as? String ?? "TTB user"
        let sourceListId = data["sourceListId"] as? String ?? ""
        let listName = data["listName"] as? String ?? "Question list"
        let questionIds = data["questionIds"] as? [String] ?? []
        let includeOwnerAnswers = data["includeOwnerAnswers"] as? Bool ?? false
        let ownerAnswerSnapshots = Self.answerSnapshots(from: data["ownerAnswerSnapshots"])
        let shareCode = data["shareCode"] as? String
        guard
            let recipientCap = integerField(
                data["recipientCap"],
                defaultValue: Self.defaultRecipientCap
            ),
            let acceptedRecipientCount = integerField(
                data["acceptedRecipientCount"],
                defaultValue: 0
            )
        else {
            return nil
        }

        let status = QuestionListShareStatus(rawValue: data["status"] as? String ?? "") ?? .unknown
        let isLinkEnabled = data["isLinkEnabled"] as? Bool ?? false
        let createdAt = (data["createdAt"] as? Timestamp)?.dateValue() ?? Date()
        let updatedAt = (data["updatedAt"] as? Timestamp)?.dateValue() ?? createdAt

        return QuestionListShare(
            id: id,
            ownerId: ownerId,
            ownerDisplayName: ownerDisplayName,
            sourceListId: sourceListId,
            listName: listName,
            questionIds: questionIds,
            includeOwnerAnswers: includeOwnerAnswers,
            ownerAnswerSnapshots: ownerAnswerSnapshots,
            shareCode: shareCode,
            recipientCap: recipientCap,
            acceptedRecipientCount: acceptedRecipientCount,
            status: status,
            isLinkEnabled: isLinkEnabled,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    private static func answerSnapshots(from value: Any?) -> [String: [String]] {
        guard let rawMap = value as? [String: Any] else { return [:] }
        var snapshots: [String: [String]] = [:]
        for (questionId, rawAnswers) in rawMap {
            guard let answers = rawAnswers as? [String] else { continue }
            snapshots[questionId] = normalizedAnswers(answers)
        }
        return snapshots
    }

    private static func integerField(
        _ value: Any?,
        defaultValue: Int
    ) -> Int? {
        guard let value else { return defaultValue }
        guard
            let number = value as? NSNumber,
            CFGetTypeID(number) != CFBooleanGetTypeID()
        else {
            return nil
        }

        switch String(cString: number.objCType) {
        case "c", "s", "i", "l", "q":
            return Int(exactly: number.int64Value)
        case "C", "S", "I", "L", "Q":
            return Int(exactly: number.uint64Value)
        default:
            return nil
        }
    }

    static func normalizedAnswers(_ answers: [String]) -> [String] {
        var padded = answers.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        while padded.count < 3 {
            padded.append("")
        }
        return Array(padded.prefix(3))
    }
}

struct QuestionListShareRecipient: Identifiable, Equatable {
    let id: String
    let shareId: String
    let recipientId: String
    let recipientDisplayName: String
    let status: QuestionListShareStatus
    let latestReplyAnswerSnapshots: [String: [String]]
    let repliedAt: Date?
    let unreadByOwner: Bool
    let acceptedAt: Date?
    let updatedAt: Date

    static func fromFirestore(
        _ data: [String: Any],
        id: String,
        shareId: String
    ) -> QuestionListShareRecipient? {
        let recipientId = data["recipientId"] as? String ?? id
        guard !recipientId.isEmpty else { return nil }

        let recipientDisplayName = data["recipientDisplayName"] as? String ?? "TTB user"
        let status = QuestionListShareStatus(rawValue: data["status"] as? String ?? "") ?? .unknown
        let latestReplyAnswerSnapshots = answerSnapshots(from: data["latestReplyAnswerSnapshots"])
        let repliedAt = (data["repliedAt"] as? Timestamp)?.dateValue()
        let unreadByOwner = data["unreadByOwner"] as? Bool ?? false
        let acceptedAt = (data["acceptedAt"] as? Timestamp)?.dateValue()
        let updatedAt = (data["updatedAt"] as? Timestamp)?.dateValue() ?? repliedAt ?? acceptedAt ?? Date()

        return QuestionListShareRecipient(
            id: recipientId,
            shareId: shareId,
            recipientId: recipientId,
            recipientDisplayName: recipientDisplayName,
            status: status,
            latestReplyAnswerSnapshots: latestReplyAnswerSnapshots,
            repliedAt: repliedAt,
            unreadByOwner: unreadByOwner,
            acceptedAt: acceptedAt,
            updatedAt: updatedAt
        )
    }

    private static func answerSnapshots(from value: Any?) -> [String: [String]] {
        guard let rawMap = value as? [String: Any] else { return [:] }
        var snapshots: [String: [String]] = [:]
        for (questionId, rawAnswers) in rawMap {
            guard let answers = rawAnswers as? [String] else { continue }
            snapshots[questionId] = QuestionListShare.normalizedAnswers(answers)
        }
        return snapshots
    }
}

struct AcceptedQuestionListShare: Identifiable, Equatable {
    var id: String { share.id }
    let share: QuestionListShare
    let recipient: QuestionListShareRecipient
}

struct QuestionListShareCreationResult: Equatable {
    let shareId: String
    let shareCode: String
    let shareURL: URL
}

struct QuestionListSharePreview: Equatable {
    let shareId: String
    let shareCode: String
    let listName: String
    let ownerDisplayName: String
    let questionCount: Int
    let includeOwnerAnswers: Bool
    let recipientCap: Int
    let acceptedRecipientCount: Int
    let isAccepted: Bool
}
