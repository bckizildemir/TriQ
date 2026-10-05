import FirebaseFirestore
import Foundation

struct AdminBadgeSeedDefinition: Decodable {
    let id: String
    let title: String
    let description: String
    let icon: String
    let requirement: String
    let titleLocalizations: [String: String]?
    let descriptionLocalizations: [String: String]?
    let requirementLocalizations: [String: String]?
    let targetCount: Int
    let type: String
    let category: String?

    var badge: Badge {
        Badge(
            id: id,
            title: title,
            description: description,
            icon: icon,
            isLocked: true,
            requirement: requirement,
            progress: 0,
            targetCount: targetCount,
            type: BadgeType(rawValue: type) ?? .total,
            category: category,
            titleLocalizations: titleLocalizations ?? [:],
            descriptionLocalizations: descriptionLocalizations ?? [:],
            requirementLocalizations: requirementLocalizations ?? [:]
        )
    }
}

final class AdminBadgeService {
    private let db: Firestore
    private let decoder: JSONDecoder
    private let bundle: Bundle

    init(
        db: Firestore = Firestore.firestore(),
        decoder: JSONDecoder = JSONDecoder(),
        bundle: Bundle = .main
    ) {
        self.db = db
        self.decoder = decoder
        self.bundle = bundle
    }

    func loadBadges() async throws -> [Badge] {
        let snapshot = try await db.collection("badges").getDocuments()

        return snapshot.documents
            .compactMap { Badge.fromFirestore($0.data(), id: $0.documentID) }
            .sorted {
                $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }
    }

    func saveBadge(_ badge: Badge) async throws {
        try await db.collection("badges").document(badge.id).setData(badge.toFirestore())
    }

    func deleteBadge(id: String) async throws {
        try await db.collection("badges").document(id).delete()
    }

    func restoreDefaultBadges() async throws -> Int {
        let snapshot = try await db.collection("badges").getDocuments()
        let existingIDs = Set(snapshot.documents.map(\.documentID))
        let missingBadges = try Self.restorableBadges(
            from: try bundledDefinitionsData(),
            excluding: existingIDs,
            decoder: decoder
        )

        guard !missingBadges.isEmpty else {
            return 0
        }

        let batch = db.batch()
        for badge in missingBadges {
            let ref = db.collection("badges").document(badge.id)
            batch.setData(badge.toFirestore(), forDocument: ref, merge: true)
        }

        try await batch.commit()
        return missingBadges.count
    }

    private func bundledDefinitionsData() throws -> Data {
        guard let url = bundle.url(forResource: "BadgeDefinitions", withExtension: "json") else {
            throw NSError(
                domain: "AdminBadgeService",
                code: 404,
                userInfo: [NSLocalizedDescriptionKey: String(localized: "badge.error.backfillMissingDefinition")]
            )
        }

        return try Data(contentsOf: url)
    }

    static func restorableBadges(
        from data: Data,
        excluding existingIDs: Set<String>,
        decoder: JSONDecoder = JSONDecoder()
    ) throws -> [Badge] {
        let definitions = try decoder.decode([AdminBadgeSeedDefinition].self, from: data)

        return definitions
            .map(\.badge)
            .filter { !existingIDs.contains($0.id) }
    }
}
