import CryptoKit
import Foundation

struct TodaysQuestionSelector {
    let count: Int
    let timeZone: TimeZone

    init(
        count: Int = 7,
        timeZone: TimeZone = TimeZone(secondsFromGMT: 0) ?? .current
    ) {
        self.count = max(0, count)
        self.timeZone = timeZone
    }

    func select(from questions: [Question], on date: Date = .now) -> [Question] {
        let dayKey = dayKey(for: date)

        // Rank over indices rather than whole `Question` values: this runs on every listener
        // snapshot, so decorating 1,000 questions would mean 1,000 struct copies (each retaining
        // ~15 reference-counted fields) before the sort even starts.
        //
        // Duplicate seeded questions can share a `contentId` (a localization or seeding bug), so
        // the lowest-id copy is kept as canonical before ranking — otherwise the same content
        // could occupy two of today's slots.
        var canonicalIndexByContentID: [String: Int] = [:]
        for index in questions.indices where questions[index].source == .seeded {
            let contentId = questions[index].contentId
            if let existingIndex = canonicalIndexByContentID[contentId] {
                if questions[index].id < questions[existingIndex].id {
                    canonicalIndexByContentID[contentId] = index
                }
            } else {
                canonicalIndexByContentID[contentId] = index
            }
        }

        let ranked = canonicalIndexByContentID.values
            .map { index in
                RankedQuestion(
                    index: index,
                    contentId: questions[index].contentId,
                    rank: rank(for: questions[index], dayKey: dayKey)
                )
            }
            .sorted(by: compareRankedQuestions)

        return ranked.prefix(count).map { questions[$0.index] }
    }

    private func dayKey(for date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = calendar.dateComponents([.year, .month, .day], from: date)

        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }

    private func rank(for question: Question, dayKey: String) -> QuestionRank {
        let payload = "\(dayKey)|\(question.contentId)"
        return QuestionRank(digest: SHA256.hash(data: Data(payload.utf8)))
    }

    private func compareRankedQuestions(_ lhs: RankedQuestion, _ rhs: RankedQuestion) -> Bool {
        guard lhs.rank == rhs.rank else { return lhs.rank < rhs.rank }
        // Ranked questions are already deduplicated by contentId, so a rank
        // collision can only happen between distinct contentIds — break the
        // tie on that instead of `id`, which is unrelated to ranking order.
        return lhs.contentId < rhs.contentId
    }
}

private struct RankedQuestion {
    let index: Int
    let contentId: String
    let rank: QuestionRank
}

/// A SHA-256 digest held as four big-endian words so ranks compare with a handful of integer
/// comparisons instead of a 64-character hex string.
///
/// The ordering is identical to comparing the lowercase hex encodings this replaced: hex digits sort
/// in nibble order (`0`–`9` then `a`–`f` in ASCII), so lexicographic order over equal-length hex
/// strings is the same as lexicographic order over the underlying bytes. Building the hex string cost
/// 32 `String(format:)` calls per question, which dominated the whole selection.
private struct QuestionRank: Comparable {
    private let word0: UInt64
    private let word1: UInt64
    private let word2: UInt64
    private let word3: UInt64

    init(digest: SHA256Digest) {
        var words: (UInt64, UInt64, UInt64, UInt64) = (0, 0, 0, 0)
        for (offset, byte) in digest.enumerated() {
            switch offset / 8 {
            case 0: words.0 = words.0 << 8 | UInt64(byte)
            case 1: words.1 = words.1 << 8 | UInt64(byte)
            case 2: words.2 = words.2 << 8 | UInt64(byte)
            default: words.3 = words.3 << 8 | UInt64(byte)
            }
        }
        (word0, word1, word2, word3) = words
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.word0, lhs.word1, lhs.word2, lhs.word3) < (rhs.word0, rhs.word1, rhs.word2, rhs.word3)
    }
}
