import Foundation

enum QuickAnswerSuggestionResolver {
    static func normalizedKey(for value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }

    static func merge(
        localCandidates: [String],
        aiCandidates: [String],
        excluding: [String],
        limit: Int
    ) -> [String] {
        guard limit > 0 else { return [] }

        let excludedKeys = Set(excluding.map(normalizedKey(for:)))
        var seenKeys = excludedKeys
        var merged: [String] = []

        for candidate in localCandidates + aiCandidates {
            let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = normalizedKey(for: trimmed)

            guard !trimmed.isEmpty, !key.isEmpty, !seenKeys.contains(key) else {
                continue
            }

            merged.append(trimmed)
            seenKeys.insert(key)

            if merged.count == limit {
                break
            }
        }

        return merged
    }
}
