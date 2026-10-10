import UIKit

/// The image attached to one answer slot.
///
/// Exactly one of these holds, which is the point. Before this type the same fact lived in three
/// parallel arrays — `images`, `selectedSuggestedImages` and `imageURLs` — whose mutual exclusivity
/// was re-established by hand at every mutation site (`QuestionCardExpandedView` cleared the other
/// two each time one was set) and whose precedence, a local pick beating a suggestion beating a
/// saved URL, was implied by the order of an `if`/`else if` chain in the save path.
enum SlotImage {
    case none

    /// Already on the backend.
    case saved(url: String, attribution: AnswerImageAttribution?)

    /// Picked from the photo library this session, not yet uploaded.
    case pendingLocal(UIImage)

    /// Chosen from search suggestions this session, not yet copied into our own storage.
    case pendingSuggestion(AnswerImageSuggestion)

    /// True when this slot still owes an upload, so the save path must wait for it.
    var isPending: Bool {
        switch self {
        case .pendingLocal, .pendingSuggestion: true
        case .none, .saved: false
        }
    }

    /// Whether this slot shows an image at all, in any state.
    ///
    /// One check where the editor used to OR three arrays together.
    var isPresent: Bool {
        if case .none = self { return false }
        return true
    }

    /// The freshly picked image, if that is what this slot holds.
    var pendingLocalImage: UIImage? {
        guard case let .pendingLocal(image) = self else { return nil }
        return image
    }

    /// The backend URL, or `nil` for every state that has none yet.
    ///
    /// A blank or whitespace-only URL reads as `nil`: that is the rule the three copies of
    /// `normalizedImageURLSlots` enforced, and it lives here now.
    var savedURL: String? {
        guard case let .saved(url, _) = self else { return nil }
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Attribution travels with a saved image only.
    ///
    /// A pending suggestion carries its attribution for display, but contributes none to a
    /// normalized answer — the attribution is written when the upload settles, alongside the URL.
    var savedAttribution: AnswerImageAttribution? {
        guard case let .saved(_, attribution) = self else { return nil }
        return attribution
    }

    /// What this slot needs uploaded, if anything.
    func pendingUpload(slotIndex: Int) -> AnswerImageUpload? {
        switch self {
        case let .pendingLocal(image):
            AnswerImageUpload(slotIndex: slotIndex, source: .local(image))
        case let .pendingSuggestion(suggestion):
            AnswerImageUpload(slotIndex: slotIndex, source: .suggestion(suggestion))
        case .none, .saved:
            nil
        }
    }
}

/// One answer: its text and its image.
struct AnswerSlot {
    var text: String
    var image: SlotImage

    static let empty = AnswerSlot(text: "", image: .none)

    init(text: String, image: SlotImage = .none) {
        self.text = text
        self.image = image
    }

    /// Whether this slot counts toward a Complete Answer: it holds text that is not blank after
    /// trimming, or an image in any state.
    var isFilled: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || image.isPresent
    }
}

/// An answer being edited — three slots, always.
///
/// The three-slot rule is enforced by the only initializer, so `count == 3` holds by construction
/// rather than by each caller remembering to pad. That rule was written out at thirteen sites across
/// five files before this type existed; the save path's copies are gone, and the remaining read-path
/// copies are recorded in `ARCHITECTURE_DEEPENING_AUDIT.md`.
///
/// Text is stored raw so it can be bound straight to a `TextField`. Trimming happens in
/// ``normalized()`` and nowhere else: normalizing on the way in would eat a space the moment the
/// user typed one mid-word.
struct AnswerDraft {
    static let slotCount = 3

    /// Pads and truncates any per-slot array to exactly ``slotCount``, so a short or over-long
    /// value — from a decode, an edit, or a caller that hasn't heard of the rule — can never
    /// produce an out-of-bounds read. Every type that stores one value per answer slot shares
    /// this instead of writing its own copy of the loop.
    static func padded<T>(_ values: [T], with filler: T) -> [T] {
        var padded = values
        while padded.count < slotCount {
            padded.append(filler)
        }
        return Array(padded.prefix(slotCount))
    }

    private var slots: [AnswerSlot]

    /// Pads and truncates to exactly ``slotCount``. The only way to build a draft.
    init(_ slots: [AnswerSlot]) {
        self.slots = Self.padded(slots, with: .empty)
    }

    /// Rebuilds an editable draft from what is already stored for a question.
    init(_ answer: NormalizedAnswer) {
        self.init((0 ..< Self.slotCount).map { index in
            AnswerSlot(
                text: answer.texts[index],
                image: answer.urls[index].map { url in
                    SlotImage.saved(url: url, attribution: answer.attributions[index])
                } ?? .none
            )
        })
    }

    subscript(index: Int) -> AnswerSlot {
        get { slots[index] }
        set { slots[index] = newValue }
    }

    var indices: Range<Int> { 0 ..< Self.slotCount }

    /// A Complete Answer: every slot is filled. Saving does not require it; the editor uses it to
    /// tell the user the answer is ready.
    var isComplete: Bool {
        indices.allSatisfy { slots[$0].isFilled }
    }

    /// The draft reduced to what gets persisted: trimmed text, resolved URLs, three of each.
    ///
    /// Slots still owing an upload contribute no URL and no attribution, which makes this value the
    /// optimistic snapshot too — the state to store now and reconcile once uploads settle.
    func normalized() -> NormalizedAnswer {
        NormalizedAnswer(
            texts: slots.map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) },
            urls: slots.map(\.image.savedURL),
            attributions: slots.map(\.image.savedAttribution)
        )
    }

    /// Uploads this draft owes, in slot order.
    var pendingUploads: [AnswerImageUpload] {
        indices.compactMap { slots[$0].image.pendingUpload(slotIndex: $0) }
    }

    var hasPendingUploads: Bool {
        slots.contains { $0.image.isPending }
    }

    /// Whether saving would change anything.
    ///
    /// A pending image always counts as a change without being compared to anything: it is new by
    /// definition, and `UIImage` has no useful equality. Everything else is decided by comparing
    /// normalized values, which is what makes the three behaviours the old `shouldPersistAnswers`
    /// special-cased fall out of one expression — an all-empty draft on an unanswered question
    /// matches the empty baseline and saves nothing, whitespace-only edits match too, and clearing
    /// an answered question does not match, so it saves.
    func hasChanges(against baseline: NormalizedAnswer) -> Bool {
        hasPendingUploads || normalized() != baseline
    }

    /// A Complete Answer that saving would change. The editor's save tick replays its haptic on
    /// this value's false-to-true edge.
    func isReadyToSave(against baseline: NormalizedAnswer) -> Bool {
        isComplete && hasChanges(against: baseline)
    }

    /// The draft as it stands once pending uploads have been handed off.
    ///
    /// Matches what the editor did by hand after starting a background save: forget the local image
    /// and the chosen suggestion, and show no URL for that slot until the upload settles.
    func clearingPendingImages() -> AnswerDraft {
        AnswerDraft(slots.map { slot in
            slot.image.isPending ? AnswerSlot(text: slot.text, image: .none) : slot
        })
    }
}

/// An answer in the shape it is stored and compared in: trimmed, resolved, three of everything.
///
/// Only ``AnswerDraft/normalized()`` produces one, and ``AnswerPersisting`` accepts nothing else.
/// That is deliberate — it is what makes "normalize before you persist" a fact about the types
/// instead of a rule a caller has to know. The old protocol had five entry points that each
/// re-normalized their arguments because any of them might be called first.
struct NormalizedAnswer: Hashable {
    let texts: [String]
    let urls: [String?]
    let attributions: [AnswerImageAttribution?]

    static let empty = NormalizedAnswer(
        texts: Array(repeating: "", count: AnswerDraft.slotCount),
        urls: Array(repeating: nil, count: AnswerDraft.slotCount),
        attributions: Array(repeating: nil, count: AnswerDraft.slotCount)
    )

    /// Pads and truncates every array, so a short or over-long decode cannot produce a bad value.
    init(texts: [String], urls: [String?], attributions: [AnswerImageAttribution?]) {
        self.texts = AnswerDraft.padded(texts, with: "")
        self.urls = AnswerDraft.padded(urls, with: nil)
        self.attributions = AnswerDraft.padded(attributions, with: nil)
    }

    /// The normalized view of what is cached for a question.
    ///
    /// The single place `UserAnswer`'s stored shape is reduced to the compared shape. Three copies of
    /// this trimming lived in `QuestionModel` and three more in the editor.
    init(_ stored: UserAnswer) {
        self.init(
            texts: stored.answers.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) },
            urls: stored.imageURLs.map { url in
                guard let trimmed = url?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !trimmed.isEmpty
                else {
                    return nil
                }
                return trimmed
            },
            attributions: stored.imageAttributions
        )
    }

    /// Whether anything here is worth storing.
    var hasContent: Bool {
        texts.contains { !$0.isEmpty } || urls.contains { $0 != nil } || attributions.contains { $0 != nil }
    }

    /// Folds settled uploads back in, leaving slots that failed as they were.
    ///
    /// Used for the second write of a save with images: the first stored the text with no URLs, this
    /// one adds the URLs that arrived.
    func applying(_ outcomes: [AnswerImageUploadOutcome]) -> NormalizedAnswer {
        var urls = self.urls
        var attributions = self.attributions
        for case let .uploaded(slotIndex, url, attribution) in outcomes {
            urls[slotIndex] = url
            attributions[slotIndex] = attribution
        }
        return NormalizedAnswer(texts: texts, urls: urls, attributions: attributions)
    }
}

/// One image a save owes the backend.
///
/// The source is a sum type, so "neither a local image nor a suggestion" cannot be built. The struct
/// this replaces held two optionals and needed a runtime branch for a combination its own factory
/// methods already prevented.
struct AnswerImageUpload {
    enum Source {
        case local(UIImage)
        case suggestion(AnswerImageSuggestion)
    }

    let slotIndex: Int
    let source: Source
}

/// How one image upload turned out. Never thrown — a failed slot must not abandon the others.
enum AnswerImageUploadOutcome {
    case uploaded(slotIndex: Int, url: String, attribution: AnswerImageAttribution?)
    case failed(slotIndex: Int, error: Error)

    var slotIndex: Int {
        switch self {
        case let .uploaded(slotIndex, _, _): slotIndex
        case let .failed(slotIndex, _): slotIndex
        }
    }

    /// The failure, if this slot failed. Used to name the first bad slot to the user.
    var failure: (slotIndex: Int, error: Error)? {
        guard case let .failed(slotIndex, error) = self else { return nil }
        return (slotIndex, error)
    }
}
