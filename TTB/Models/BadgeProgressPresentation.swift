import Foundation

struct BadgeProgressPresentation: Equatable {
    let displayText: String
    let currentCount: Int
    let showsProgressBar: Bool
    let accessibilityValue: String
}

extension Badge {
    func progressPresentation(
        preferredLanguageCodes: [String] = AppLocalization.preferredLanguageCodes
    ) -> BadgeProgressPresentation? {
        guard targetCount > 0 else {
            return nil
        }

        let currentCount = resolvedCurrentCount
        let displayText = BadgeProgressPresentation.displayText(
            currentCount: currentCount,
            targetCount: targetCount,
            type: type,
            preferredLanguageCodes: preferredLanguageCodes
        )

        return BadgeProgressPresentation(
            displayText: displayText,
            currentCount: currentCount,
            showsProgressBar: isLocked,
            accessibilityValue: displayText
        )
    }

    private var resolvedCurrentCount: Int {
        guard targetCount > 0 else {
            return 0
        }

        guard progress.isFinite else {
            return 0
        }

        if progress >= 1 {
            return targetCount
        }

        let rawCount = Int(floor(progress * Double(targetCount)))
        return min(max(rawCount, 0), targetCount)
    }
}

private extension BadgeProgressPresentation {
    static let questionFormatFallbacks: [String: String] = [
        "en": "%lld / %lld questions",
        "tr": "%lld / %lld soru"
    ]

    static let dayFormatFallbacks: [String: String] = [
        "en": "%lld / %lld days",
        "tr": "%lld / %lld gün"
    ]

    static func displayText(
        currentCount: Int,
        targetCount: Int,
        type: BadgeType,
        preferredLanguageCodes: [String]
    ) -> String {
        let locale = locale(for: preferredLanguageCodes)
        let key: String
        let fallbackMap: [String: String]

        switch type {
        case .streak:
            key = "badge.progress.daysFormat"
            fallbackMap = dayFormatFallbacks
        case .total, .category:
            key = "badge.progress.questionsFormat"
            fallbackMap = questionFormatFallbacks
        }

        let format = localizedFormat(
            key: key,
            fallbackMap: fallbackMap,
            preferredLanguageCodes: preferredLanguageCodes,
            locale: locale
        )

        return String(
            format: format,
            locale: locale,
            Int64(currentCount),
            Int64(targetCount)
        )
    }

    static func localizedFormat(
        key: String,
        fallbackMap: [String: String],
        preferredLanguageCodes: [String],
        locale: Locale
    ) -> String {
        for code in preferredLanguageCodes {
            for candidate in localizationCandidates(for: code) {
                guard
                    let path = Bundle.main.path(forResource: candidate, ofType: "lproj"),
                    let bundle = Bundle(path: path)
                else {
                    continue
                }

                let localizedValue = bundle.localizedString(forKey: key, value: key, table: nil)
                if localizedValue != key {
                    return localizedValue
                }
            }
        }

        return AppLocalization.resolve(
            fallbackMap,
            legacy: fallbackMap[AppLocalization.fallbackLanguageCode],
            preferredLanguageCodes: preferredLanguageCodes
        )
    }

    static func locale(for preferredLanguageCodes: [String]) -> Locale {
        let identifier = preferredLanguageCodes.first ?? AppLocalization.fallbackLanguageCode
        return Locale(identifier: identifier)
    }

    static func localizationCandidates(for code: String) -> [String] {
        var candidates: [String] = []

        if !code.isEmpty {
            candidates.append(code)
        }

        if let base = code.split(separator: "-").first.map(String.init), !base.isEmpty {
            candidates.append(base)
        }

        return Array(NSOrderedSet(array: candidates)) as? [String] ?? candidates
    }
}
