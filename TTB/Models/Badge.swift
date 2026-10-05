import Foundation

enum BadgeType: String, Codable {
    case total = "total"
    case category = "category"
    case streak = "streak"
}

struct Badge: Identifiable, Codable, Equatable {
    let id: String
    let titleLocalizations: [String: String]
    let descriptionLocalizations: [String: String]
    let icon: String
    let isLocked: Bool
    let requirementLocalizations: [String: String]
    let progress: Double
    let targetCount: Int
    let type: BadgeType
    let category: String?
    private let legacyTitle: String
    private let legacyDescription: String
    private let legacyRequirement: String

    var title: String {
        resolvedTitle(preferredLanguageCodes: AppLocalization.preferredLanguageCodes)
    }

    var description: String {
        resolvedDescription(preferredLanguageCodes: AppLocalization.preferredLanguageCodes)
    }

    var requirement: String {
        resolvedRequirement(preferredLanguageCodes: AppLocalization.preferredLanguageCodes)
    }

    func resolvedTitle(preferredLanguageCodes: [String]) -> String {
        AppLocalization.resolve(
            titleLocalizations,
            legacy: legacyTitle,
            preferredLanguageCodes: preferredLanguageCodes
        )
    }

    func resolvedDescription(preferredLanguageCodes: [String]) -> String {
        AppLocalization.resolve(
            descriptionLocalizations,
            legacy: legacyDescription,
            preferredLanguageCodes: preferredLanguageCodes
        )
    }

    func resolvedRequirement(preferredLanguageCodes: [String]) -> String {
        AppLocalization.resolve(
            requirementLocalizations,
            legacy: legacyRequirement,
            preferredLanguageCodes: preferredLanguageCodes
        )
    }

    init(
        id: String,
        title: String,
        description: String,
        icon: String,
        isLocked: Bool,
        requirement: String,
        progress: Double,
        targetCount: Int = 0,
        type: BadgeType = .total,
        category: String? = nil,
        titleLocalizations: [String: String] = [:],
        descriptionLocalizations: [String: String] = [:],
        requirementLocalizations: [String: String] = [:]
    ) {
        self.id = id
        self.legacyTitle = title
        self.legacyDescription = description
        self.icon = icon
        self.isLocked = isLocked
        self.legacyRequirement = requirement
        self.progress = progress
        self.targetCount = targetCount
        self.type = type
        self.category = category
        self.titleLocalizations = titleLocalizations
        self.descriptionLocalizations = descriptionLocalizations
        self.requirementLocalizations = requirementLocalizations
    }
    
    static func fromFirestore(_ data: [String: Any], id: String) -> Badge? {
        let typeString = data["type"] as? String ?? "total"
        let type = BadgeType(rawValue: typeString) ?? .total
        let titleLocalizations = localizedMap(from: data["titleLocalizations"])
        let descriptionLocalizations = localizedMap(from: data["descriptionLocalizations"])
        let requirementLocalizations = localizedMap(from: data["requirementLocalizations"])
        
        return Badge(
            id: id,
            title: data["title"] as? String ?? "Unnamed Badge",
            description: data["description"] as? String ?? "No description",
            icon: data["icon"] as? String ?? "star.fill",
            isLocked: !(data["unlocked"] as? Bool ?? false),
            requirement: data["requirement"] as? String ?? "Complete tasks to unlock",
            progress: data["progress"] as? Double ?? 0.0,
            targetCount: data["targetCount"] as? Int ?? 0,
            type: type,
            category: data["category"] as? String,
            titleLocalizations: titleLocalizations,
            descriptionLocalizations: descriptionLocalizations,
            requirementLocalizations: requirementLocalizations
        )
    }
    
    func toFirestore() -> [String: Any] {
        var data: [String: Any] = [
            "title": legacyTitle,
            "description": legacyDescription,
            "icon": icon,
            "requirement": legacyRequirement,
            "targetCount": targetCount,
            "type": type.rawValue,
            "unlocked": !isLocked,
            "progress": progress
        ]

        if !titleLocalizations.isEmpty {
            data["titleLocalizations"] = titleLocalizations
        }

        if !descriptionLocalizations.isEmpty {
            data["descriptionLocalizations"] = descriptionLocalizations
        }

        if !requirementLocalizations.isEmpty {
            data["requirementLocalizations"] = requirementLocalizations
        }
        
        if let category = category {
            data["category"] = category
        }
        
        return data
    }

    private static func localizedMap(from value: Any?) -> [String: String] {
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
}
