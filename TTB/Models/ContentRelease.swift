import FirebaseFirestore
import Foundation

enum ContentReleaseStatus: String, CaseIterable, Codable {
    case draft
    case scheduled
    case published
    case canceled
}

struct ContentRelease: Identifiable, Equatable {
    let id: String
    var localizedTitle: [String: String]
    var localizedBody: [String: String]
    var categoryIds: [String]
    var questionIds: [String]
    var status: ContentReleaseStatus
    var scheduledAt: Date?
    var publishedAt: Date?
    let createdAt: Date
    var updatedAt: Date?
    let createdBy: String?

    init(
        id: String = UUID().uuidString,
        localizedTitle: [String: String],
        localizedBody: [String: String],
        categoryIds: [String],
        questionIds: [String],
        status: ContentReleaseStatus = .draft,
        scheduledAt: Date? = nil,
        publishedAt: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date? = nil,
        createdBy: String? = nil
    ) {
        self.id = id
        self.localizedTitle = localizedTitle
        self.localizedBody = localizedBody
        self.categoryIds = categoryIds
        self.questionIds = questionIds
        self.status = status
        self.scheduledAt = scheduledAt
        self.publishedAt = publishedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.createdBy = createdBy
    }

    var title: String {
        AppLocalization.resolve(localizedTitle, legacy: "")
    }

    var body: String {
        AppLocalization.resolve(localizedBody, legacy: "")
    }

    var isPublished: Bool {
        status == .published
    }

    static func fromFirestore(_ data: [String: Any], id: String) -> ContentRelease {
        let scheduledAt = (data["scheduledAt"] as? Timestamp)?.dateValue()
        let publishedAt = (data["publishedAt"] as? Timestamp)?.dateValue()

        return ContentRelease(
            id: id,
            localizedTitle: localizedMap(from: data["localizedTitle"]),
            localizedBody: localizedMap(from: data["localizedBody"]),
            categoryIds: data["categoryIds"] as? [String] ?? [],
            questionIds: data["questionIds"] as? [String] ?? [],
            status: resolvedStatus(from: data, scheduledAt: scheduledAt, publishedAt: publishedAt),
            scheduledAt: scheduledAt,
            publishedAt: publishedAt,
            createdAt: (data["createdAt"] as? Timestamp)?.dateValue() ?? Date(),
            updatedAt: (data["updatedAt"] as? Timestamp)?.dateValue(),
            createdBy: data["createdBy"] as? String
        )
    }

    func toFirestore() -> [String: Any] {
        var data: [String: Any] = [
            "localizedTitle": localizedTitle,
            "localizedBody": localizedBody,
            "categoryIds": categoryIds,
            "questionIds": questionIds,
            "status": status.rawValue,
            "createdAt": Timestamp(date: createdAt),
        ]

        if let scheduledAt {
            data["scheduledAt"] = Timestamp(date: scheduledAt)
        }

        if let publishedAt {
            data["publishedAt"] = Timestamp(date: publishedAt)
        }

        if let updatedAt {
            data["updatedAt"] = Timestamp(date: updatedAt)
        }

        if let createdBy {
            data["createdBy"] = createdBy
        }

        return data
    }

    static func localizedMap(from rawValue: Any?) -> [String: String] {
        guard let rawMap = rawValue as? [String: Any] else { return [:] }
        return rawMap.reduce(into: [:]) { result, pair in
            if let value = pair.value as? String, !value.isEmpty {
                result[pair.key] = value
            }
        }
    }

    private static func resolvedStatus(
        from data: [String: Any],
        scheduledAt: Date?,
        publishedAt: Date?
    ) -> ContentReleaseStatus {
        if let rawStatus = data["status"] as? String,
           let status = ContentReleaseStatus(rawValue: rawStatus) {
            return status
        }

        if publishedAt != nil {
            return .published
        }

        if scheduledAt != nil {
            return .scheduled
        }

        // Legacy release documents predate the simplified publish flow and are
        // safer to treat as published history than as hidden drafts.
        return .published
    }
}
