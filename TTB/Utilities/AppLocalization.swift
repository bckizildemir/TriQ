import Foundation
import Synchronization

enum AppLocalization {
    static let fallbackLanguageCode = "tr"

    static var currentLocale: Locale {
        .autoupdatingCurrent
    }

    static var currentLanguageCode: String {
        preferredLanguageCodes.first ?? fallbackLanguageCode
    }

    static var prefersEnglish: Bool {
        prefersEnglish(for: currentLanguageCode)
    }

    static func prefersEnglish(for languageCode: String) -> Bool {
        languageCode
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: { $0 == "-" || $0 == "_" })
            .first?
            .lowercased() == "en"
    }

    static var aiPromptLanguageName: String {
        promptLanguageName(forLanguageCode: currentLanguageCode)
    }

    /// Read transitively from every `Question.text` and `Category.displayName`, so it runs per card
    /// body, per accessibility label, and per item in every search filter. Resolving it constructs a
    /// `Locale` per preferred language, so the result is memoized against the system's
    /// preferred-language list and only recomputed when that list actually changes.
    static var preferredLanguageCodes: [String] {
        preferredLanguageCodesCache.codes(for: Locale.preferredLanguages)
    }

    private static let preferredLanguageCodesCache = PreferredLanguageCodesCache()

    static func preferredLanguageCodes(for preferredLanguages: [String]) -> [String] {
        var codes: [String] = []

        for identifier in preferredLanguages {
            let locale = Locale(identifier: identifier)
            if let exact = locale.identifier.replacingOccurrences(of: "_", with: "-").nilIfEmpty {
                codes.append(exact)
            }

            if let base = locale.language.languageCode?.identifier.nilIfEmpty {
                codes.append(base)
            } else if let base = identifier
                .split(whereSeparator: { $0 == "-" || $0 == "_" })
                .first
                .map(String.init)?
                .nilIfEmpty {
                codes.append(base)
            }
        }

        codes.append(fallbackLanguageCode)

        var unique: [String] = []
        for code in codes where !unique.contains(code) {
            unique.append(code)
        }
        return unique
    }

    static func promptLanguageName(forLanguageCode languageCode: String) -> String {
        prefersEnglish(for: languageCode) ? "English" : "Turkish"
    }

    static func languageCode(forText text: String) -> String? {
        let normalized = text
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "tr_TR"))
            .lowercased()
        let words = Set(normalized.split { !$0.isLetter }.map(String.init))

        if text.range(of: #"[çğıöşüÇĞİÖŞÜ]"#, options: .regularExpression) != nil ||
            !words.isDisjoint(with: turkishSignalWords) {
            return "tr"
        }

        if !words.isDisjoint(with: englishSignalWords) {
            return "en"
        }

        return nil
    }

    static func resolve(_ map: [String: String]?, legacy: String?) -> String {
        resolve(map, legacy: legacy, preferredLanguageCodes: preferredLanguageCodes)
    }

    static func resolve(
        _ map: [String: String]?,
        legacy: String?,
        preferredLanguageCodes preferredCodes: [String]
    ) -> String {
        guard let map, !map.isEmpty else {
            return legacy ?? ""
        }

        for code in preferredCodes {
            if let value = map[code], !value.isEmpty {
                return value
            }

            if let base = code.split(separator: "-").first.map(String.init),
               let value = map[base], !value.isEmpty {
                return value
            }
        }

        return legacy ?? map.values.first ?? ""
    }
}

/// Memoizes `AppLocalization.preferredLanguageCodes` keyed on the system preferred-language list.
/// Keying on the list itself — rather than observing a locale-change notification — means the cache
/// can never serve a stale answer. Locked because localized text is resolved from the main actor and
/// from the service actors alike; the `Mutex` is what makes the shared instance `Sendable`.
private final class PreferredLanguageCodesCache: Sendable {
    private struct State {
        var preferredLanguages: [String]?
        var codes: [String] = []
    }

    private let state = Mutex(State())

    func codes(for preferredLanguages: [String]) -> [String] {
        state.withLock { cached in
            if cached.preferredLanguages == preferredLanguages {
                return cached.codes
            }

            let codes = AppLocalization.preferredLanguageCodes(for: preferredLanguages)
            cached = State(preferredLanguages: preferredLanguages, codes: codes)
            return codes
        }
    }
}

private let turkishSignalWords: Set<String> = [
    "ben", "beni", "benim", "bir", "bu", "bunu", "cok", "daha", "de", "da",
    "degil", "diye", "en", "icin", "ile", "ilk", "iyi", "karar", "kendimi",
    "ne", "neler", "oldu", "olarak", "oyun", "oyunu", "sabah", "seni", "son", "ve", "verdim",
    "ya", "uyandiginda", "uyandigimda", "ruyami", "hatirlamaya", "calistim"
]

private let englishSignalWords: Set<String> = [
    "a", "about", "and", "are", "came", "charades", "dare", "did", "do", "first", "for", "i",
    "in", "mind", "morning", "my", "of", "that", "the", "things", "this",
    "to", "pictionary", "truth", "was", "were", "what", "when", "which", "who", "why", "woke", "you",
    "your"
]

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
