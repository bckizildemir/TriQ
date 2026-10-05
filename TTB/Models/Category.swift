import FirebaseFirestore
import Foundation

struct Category: Identifiable, Equatable {
    let id: String
    let localizedNames: [String: String]
    let iconSystemName: String
    let colorToken: CategoryColorToken
    let sortOrder: Int
    let isActive: Bool
    let isAnnounced: Bool
    let createdAt: Date
    let updatedAt: Date?
    let createdBy: String?
    let announcedAt: Date?
    let announcedInReleaseId: String?

    init(
        id: String,
        localizedNames: [String: String],
        iconSystemName: String,
        colorToken: CategoryColorToken? = nil,
        sortOrder: Int,
        isActive: Bool = true,
        isAnnounced: Bool = true,
        createdAt: Date = Date(),
        updatedAt: Date? = nil,
        createdBy: String? = nil,
        announcedAt: Date? = nil,
        announcedInReleaseId: String? = nil
    ) {
        self.id = id
        self.localizedNames = localizedNames
        self.iconSystemName = iconSystemName
        self.colorToken = colorToken ?? Self.defaultColorToken(for: id)
        self.sortOrder = sortOrder
        self.isActive = isActive
        self.isAnnounced = isAnnounced
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.createdBy = createdBy
        self.announcedAt = announcedAt
        self.announcedInReleaseId = announcedInReleaseId
    }

    var displayName: String {
        AppLocalization.resolve(localizedNames, legacy: id)
    }

    func displayName(preferredLanguageCodes: [String]) -> String {
        AppLocalization.resolve(
            localizedNames,
            legacy: id,
            preferredLanguageCodes: preferredLanguageCodes
        )
    }

    static func fromFirestore(_ data: [String: Any], id: String) -> Category {
        Category(
            id: id,
            localizedNames: localizedNames(from: data["localizedNames"]),
            iconSystemName: data["iconSystemName"] as? String ?? fallbackIcon(for: id),
            colorToken: colorToken(from: data["colorToken"], categoryID: id),
            sortOrder: data["sortOrder"] as? Int ?? 0,
            isActive: data["isActive"] as? Bool ?? true,
            isAnnounced: data["isAnnounced"] as? Bool ?? true,
            createdAt: (data["createdAt"] as? Timestamp)?.dateValue() ?? Date(),
            updatedAt: (data["updatedAt"] as? Timestamp)?.dateValue(),
            createdBy: data["createdBy"] as? String,
            announcedAt: (data["announcedAt"] as? Timestamp)?.dateValue(),
            announcedInReleaseId: data["announcedInReleaseId"] as? String
        )
    }

    func toFirestore() -> [String: Any] {
        var data: [String: Any] = [
            "localizedNames": localizedNames,
            "iconSystemName": iconSystemName,
            "colorToken": colorToken.rawValue,
            "sortOrder": sortOrder,
            "isActive": isActive,
            "isAnnounced": isAnnounced,
            "createdAt": Timestamp(date: createdAt)
        ]

        if let updatedAt {
            data["updatedAt"] = Timestamp(date: updatedAt)
        }

        if let createdBy {
            data["createdBy"] = createdBy
        }

        if let announcedAt {
            data["announcedAt"] = Timestamp(date: announcedAt)
        }

        if let announcedInReleaseId {
            data["announcedInReleaseId"] = announcedInReleaseId
        }

        return data
    }

    static func localizedNames(from rawValue: Any?) -> [String: String] {
        guard let rawMap = rawValue as? [String: Any] else { return [:] }
        return rawMap.reduce(into: [:]) { result, pair in
            if let value = pair.value as? String, !value.isEmpty {
                result[pair.key] = value
            }
        }
    }

    static func colorToken(from rawValue: Any?, categoryID: String) -> CategoryColorToken {
        guard let rawValue = rawValue as? String,
              let token = CategoryColorToken(rawValue: rawValue)
        else {
            return defaultColorToken(for: categoryID)
        }

        return token
    }

    static func fallbackCategory(for id: String) -> Category {
        defaultCategories.first(where: { $0.id == id })
        ?? Category(
            id: id,
            localizedNames: [
                "en": id,
                "tr": id
            ],
            iconSystemName: fallbackIcon(for: id),
            colorToken: defaultColorToken(for: id),
            sortOrder: defaultCategories.count + 1
        )
    }

    static func fallbackTitle(for id: String) -> String {
        fallbackCategory(for: id).displayName
    }

    static func fallbackIcon(for id: String) -> String {
        switch id {
        case "Daily":
            "calendar"
        case "Personal":
            "person.fill"
        case "SelfDiscovery":
            "sparkles"
        case "Relationships":
            "heart.fill"
        case "SocialLife":
            "person.2.fill"
        case "Career":
            "briefcase.fill"
        case "Health":
            "heart.text.square.fill"
        case "Goals":
            "flag.fill"
        case "Creativity":
            "paintbrush.fill"
        case "Food":
            "fork.knife"
        case "MoviesTV":
            "tv.fill"
        case "Books":
            "book.fill"
        case "Music":
            "music.note"
        case "Games":
            "gamecontroller.fill"
        case "Travel":
            "airplane"
        case "Style":
            "tshirt.fill"
        case "DigitalLife":
            "iphone"
        case "Hobbies":
            "figure.run"
        case "Childhood":
            "teddybear.fill"
        case "Home":
            "house.fill"
        case "Humor":
            "face.smiling.fill"
        case "Boundaries":
            "hand.raised.fill"
        case "Recommendations":
            "hand.thumbsup.fill"
        case "Photography":
            "camera.fill"
        default:
            "square.grid.2x2"
        }
    }

    static func defaultColorToken(for id: String) -> CategoryColorToken {
        switch id {
        case "Daily":
            .systemBlue
        case "Personal":
            .systemPurple
        case "SelfDiscovery":
            .systemPurple
        case "Relationships":
            .systemPink
        case "SocialLife":
            .systemMint
        case "Career":
            .systemIndigo
        case "Health":
            .systemGreen
        case "Goals":
            .systemOrange
        case "Creativity":
            .systemTeal
        case "Food":
            .systemRed
        case "MoviesTV":
            .systemIndigo
        case "Books":
            .systemBrown
        case "Music":
            .systemPink
        case "Games":
            .systemCyan
        case "Travel":
            .systemBlue
        case "Style":
            .systemPurple
        case "DigitalLife":
            .systemGray
        case "Hobbies":
            .systemGreen
        case "Childhood":
            .systemYellow
        case "Home":
            .systemBrown
        case "Humor":
            .systemYellow
        case "Boundaries":
            .systemRed
        case "Recommendations":
            .systemMint
        case "Photography":
            .systemCyan
        default:
            .systemBlue
        }
    }

    static let defaultCategories: [Category] = [
        Category(
            id: "Daily",
            localizedNames: [
                "en": "Daily",
                "tr": "Günlük"
            ],
            iconSystemName: "calendar",
            colorToken: .systemBlue,
            sortOrder: 0
        ),
        Category(
            id: "Personal",
            localizedNames: [
                "en": "Personal",
                "tr": "Kişisel"
            ],
            iconSystemName: "person.fill",
            colorToken: .systemPurple,
            sortOrder: 1
        ),
        Category(
            id: "SelfDiscovery",
            localizedNames: [
                "en": "Self Discovery",
                "tr": "Kendini Tanıma"
            ],
            iconSystemName: "sparkles",
            colorToken: .systemPurple,
            sortOrder: 2
        ),
        Category(
            id: "Relationships",
            localizedNames: [
                "en": "Relationships",
                "tr": "İlişkiler"
            ],
            iconSystemName: "heart.fill",
            colorToken: .systemPink,
            sortOrder: 3
        ),
        Category(
            id: "SocialLife",
            localizedNames: [
                "en": "Social Life",
                "tr": "Sosyal Hayat"
            ],
            iconSystemName: "person.2.fill",
            colorToken: .systemMint,
            sortOrder: 4
        ),
        Category(
            id: "Career",
            localizedNames: [
                "en": "Career",
                "tr": "Kariyer"
            ],
            iconSystemName: "briefcase.fill",
            colorToken: .systemIndigo,
            sortOrder: 5
        ),
        Category(
            id: "Health",
            localizedNames: [
                "en": "Health",
                "tr": "Sağlık"
            ],
            iconSystemName: "heart.text.square.fill",
            colorToken: .systemGreen,
            sortOrder: 6
        ),
        Category(
            id: "Goals",
            localizedNames: [
                "en": "Goals",
                "tr": "Hedefler"
            ],
            iconSystemName: "flag.fill",
            colorToken: .systemOrange,
            sortOrder: 7
        ),
        Category(
            id: "Creativity",
            localizedNames: [
                "en": "Creativity",
                "tr": "Yaratıcılık"
            ],
            iconSystemName: "paintbrush.fill",
            colorToken: .systemTeal,
            sortOrder: 8
        ),
        Category(
            id: "Food",
            localizedNames: [
                "en": "Food",
                "tr": "Yeme İçme"
            ],
            iconSystemName: "fork.knife",
            colorToken: .systemRed,
            sortOrder: 9
        ),
        Category(
            id: "MoviesTV",
            localizedNames: [
                "en": "Movies & TV",
                "tr": "Film ve Dizi"
            ],
            iconSystemName: "tv.fill",
            colorToken: .systemIndigo,
            sortOrder: 10
        ),
        Category(
            id: "Books",
            localizedNames: [
                "en": "Books",
                "tr": "Kitaplar"
            ],
            iconSystemName: "book.fill",
            colorToken: .systemBrown,
            sortOrder: 11
        ),
        Category(
            id: "Music",
            localizedNames: [
                "en": "Music",
                "tr": "Müzik"
            ],
            iconSystemName: "music.note",
            colorToken: .systemPink,
            sortOrder: 12
        ),
        Category(
            id: "Games",
            localizedNames: [
                "en": "Games",
                "tr": "Oyunlar"
            ],
            iconSystemName: "gamecontroller.fill",
            colorToken: .systemCyan,
            sortOrder: 13
        ),
        Category(
            id: "Travel",
            localizedNames: [
                "en": "Travel",
                "tr": "Seyahat"
            ],
            iconSystemName: "airplane",
            colorToken: .systemBlue,
            sortOrder: 14
        ),
        Category(
            id: "Style",
            localizedNames: [
                "en": "Style",
                "tr": "Stil"
            ],
            iconSystemName: "tshirt.fill",
            colorToken: .systemPurple,
            sortOrder: 15
        ),
        Category(
            id: "DigitalLife",
            localizedNames: [
                "en": "Digital Life",
                "tr": "Dijital Hayat"
            ],
            iconSystemName: "iphone",
            colorToken: .systemGray,
            sortOrder: 16
        ),
        Category(
            id: "Hobbies",
            localizedNames: [
                "en": "Hobbies",
                "tr": "Hobiler"
            ],
            iconSystemName: "figure.run",
            colorToken: .systemGreen,
            sortOrder: 17
        ),
        Category(
            id: "Childhood",
            localizedNames: [
                "en": "Childhood",
                "tr": "Çocukluk"
            ],
            iconSystemName: "teddybear.fill",
            colorToken: .systemYellow,
            sortOrder: 18
        ),
        Category(
            id: "Home",
            localizedNames: [
                "en": "Home",
                "tr": "Ev"
            ],
            iconSystemName: "house.fill",
            colorToken: .systemBrown,
            sortOrder: 19
        ),
        Category(
            id: "Humor",
            localizedNames: [
                "en": "Humor",
                "tr": "Mizah"
            ],
            iconSystemName: "face.smiling.fill",
            colorToken: .systemYellow,
            sortOrder: 20
        ),
        Category(
            id: "Boundaries",
            localizedNames: [
                "en": "Boundaries",
                "tr": "Sınırlar"
            ],
            iconSystemName: "hand.raised.fill",
            colorToken: .systemRed,
            sortOrder: 21
        ),
        Category(
            id: "Recommendations",
            localizedNames: [
                "en": "Recommendations",
                "tr": "Öneriler"
            ],
            iconSystemName: "hand.thumbsup.fill",
            colorToken: .systemMint,
            sortOrder: 22
        ),
        Category(
            id: "Photography",
            localizedNames: [
                "en": "Photography",
                "tr": "Fotoğraf"
            ],
            iconSystemName: "camera.fill",
            colorToken: .systemCyan,
            sortOrder: 23
        ),
    ]
}

enum CategoryColorToken: String, CaseIterable, Equatable {
    case systemRed
    case systemOrange
    case systemYellow
    case systemGreen
    case systemMint
    case systemTeal
    case systemCyan
    case systemBlue
    case systemIndigo
    case systemPurple
    case systemPink
    case systemBrown
    case systemGray
}
