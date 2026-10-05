import Foundation
import UIKit
@testable import TTB

// In-memory adapters for the four answer-draft ports.
//
// These are the whole reason the ports exist. Before them, `questionService` was a concrete optional
// and every test ran the branch where persistence silently did nothing — so the optimistic write,
// the rollback, the upload fan-out and the compare-and-swap were all unreachable, and the tests that
// existed would have passed with persistence entirely broken.
//
// They live in Tests/ deliberately. The project uses file-system-synchronized groups, so a fake under
// TTB/ would join the app target and ship in the release binary — which is exactly what FIX-1 was.

/// Records what was persisted, and fails whichever calls a test asks it to.
///
/// Failures are addressed by 1-based call number because the save path can persist twice: once with
/// the text, once again with the image URLs that arrived afterwards.
actor FakeAnswerPersister: AnswerPersisting {
    struct SaveFailure: Error {}

    private let failingCalls: Set<Int>
    private var callCount = 0
    private(set) var saved: [NormalizedAnswer] = []

    init(failingCalls: Set<Int> = []) {
        self.failingCalls = failingCalls
    }

    func save(_ answer: NormalizedAnswer, for questionId: String) async throws {
        callCount += 1
        if failingCalls.contains(callCount) {
            throw SaveFailure()
        }
        saved.append(answer)
    }

    var saveCount: Int { callCount }
}

/// Scripted per-slot upload results, so partial failure is a first-class test case.
actor FakeAnswerImageStore: AnswerImageStoring {
    struct UploadFailure: Error {
        let slotIndex: Int
    }

    private let urls: [Int: String]
    private let failingSlots: Set<Int>
    private(set) var uploadedSlots: [Int] = []
    private(set) var deletedSlots: [Int] = []

    init(urls: [Int: String] = [:], failingSlots: Set<Int> = []) {
        self.urls = urls
        self.failingSlots = failingSlots
    }

    func upload(_ upload: AnswerImageUpload, questionId: String) async -> AnswerImageUploadOutcome {
        uploadedSlots.append(upload.slotIndex)

        if failingSlots.contains(upload.slotIndex) {
            return .failed(slotIndex: upload.slotIndex, error: UploadFailure(slotIndex: upload.slotIndex))
        }

        return .uploaded(
            slotIndex: upload.slotIndex,
            url: urls[upload.slotIndex] ?? "https://example.com/slot-\(upload.slotIndex).jpg",
            attribution: nil
        )
    }

    func deleteAnswerImage(questionId: String, slotIndex: Int) async throws {
        deletedSlots.append(slotIndex)
    }
}

/// Stands in for `QuestionModel`: holds the cached answer and collects reported failures.
@MainActor
final class FakeAnswerHost: AnswerCaching, AnswerSaveErrorReporting {
    var stored: [String: UserAnswer] = [:]
    private(set) var reported: [AnswerSaveError] = []
    private(set) var cacheWrites = 0

    init(stored: [String: UserAnswer] = [:]) {
        self.stored = stored
    }

    func currentAnswer(for questionId: String) -> UserAnswer? {
        stored[questionId]
    }

    func cache(_ answer: NormalizedAnswer, for questionId: String) {
        cacheWrites += 1
        stored[questionId] = UserAnswer(
            questionId: questionId,
            userId: stored[questionId]?.userId ?? "test-user",
            answers: answer.texts,
            answeredAt: Date(),
            imageURLs: answer.urls,
            imageAttributions: answer.attributions
        )
    }

    func restore(_ previous: UserAnswer?, for questionId: String) {
        if let previous {
            stored[questionId] = previous
        } else {
            stored.removeValue(forKey: questionId)
        }
    }

    func report(_ error: AnswerSaveError) {
        reported.append(error)
    }

    /// What is cached, in the shape assertions care about.
    func normalized(_ questionId: String) -> NormalizedAnswer? {
        stored[questionId].map(NormalizedAnswer.init)
    }
}

// MARK: - Builders

extension AnswerDraft {
    /// A draft from three texts, optionally with an image in some slots.
    static func fixture(_ texts: [String], images: [Int: SlotImage] = [:]) -> AnswerDraft {
        AnswerDraft(texts.enumerated().map { index, text in
            AnswerSlot(text: text, image: images[index] ?? .none)
        })
    }
}

extension UserAnswer {
    static func fixture(
        questionId: String,
        answers: [String],
        imageURLs: [String?] = [nil, nil, nil],
        imageAttributions: [AnswerImageAttribution?] = [nil, nil, nil],
        userId: String = "test-user",
        answeredAt: Date = Date(timeIntervalSince1970: 1_000)
    ) -> UserAnswer {
        UserAnswer(
            questionId: questionId,
            userId: userId,
            answers: answers,
            answeredAt: answeredAt,
            imageURLs: imageURLs,
            imageAttributions: imageAttributions
        )
    }
}
