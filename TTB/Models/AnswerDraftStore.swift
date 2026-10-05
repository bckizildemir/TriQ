import Foundation
import SwiftUI

/// Everything one save needs, decided before any of it happens.
///
/// Deciding up front is what removes the ordering hazard: the old protocol had five methods a caller
/// had to invoke in a mandated sequence, each re-deriving what the previous one had already computed,
/// with nothing in the type system to stop them being called out of order.
struct AnswerSavePlan {
    let questionId: String

    /// What the editor opened with. Only used to notice images the user removed.
    let baseline: NormalizedAnswer

    /// What the cache held before the optimistic write, kept verbatim so a rollback restores it
    /// exactly — same timestamp, same user id — rather than looking like a fresh answer.
    let previous: UserAnswer?

    /// What to show and store immediately. Slots still owing an upload contribute no URL yet.
    let optimistic: NormalizedAnswer

    let uploads: [AnswerImageUpload]
}

/// Saves an answer draft: one entry point, one order, one place the choreography lives.
///
/// Replaces ~250 lines of persistence orchestration that sat in `QuestionCardExpandedView` and three
/// entry points on `QuestionModel` that could only be called in one sequence. The store owns the
/// choreography and nothing else — the cached answer stays on `QuestionModel`, where its readers and
/// the Firestore listener that feeds it already are.
///
/// A save outlives the editor that starts it: ``save(_:baseline:for:in:)`` returns as soon as the
/// optimistic write is visible, and the uploads carry on afterwards. That is why failures are
/// reported to a host rather than returned, and why the three phases are separately callable — it is
/// what lets a test await the part that used to be unobservable.
@MainActor
final class AnswerDraftStore {
    private nonisolated let persister: AnswerPersisting?
    private nonisolated let images: AnswerImageStoring

    /// `persister` is optional to preserve the existing local mode: with no backend configured,
    /// saving updates the cache and nothing else, exactly as `persistAnswers` did when
    /// `questionService` was nil. AD-3 and AD-5 are where that optionality should go away.
    nonisolated init(persister: AnswerPersisting?, images: AnswerImageStoring) {
        self.persister = persister
        self.images = images
    }

    /// Starts a save. Returns whether there was anything to do.
    ///
    /// The caller may dismiss as soon as this returns; the rest completes in the background.
    @discardableResult
    func save(
        _ draft: AnswerDraft,
        baseline: NormalizedAnswer,
        for questionId: String,
        in host: any AnswerDraftHost
    ) -> Bool {
        guard let plan = plan(for: draft, baseline: baseline, questionId: questionId, in: host) else {
            return false
        }

        applyOptimistically(plan, in: host)
        Task { await finish(plan, in: host) }
        return true
    }

    /// Decides whether this draft is worth saving, and what saving it means.
    ///
    /// Two questions, both answered by comparing normalized values. Did the editor change anything
    /// since it opened? And is the result actually different from what is cached? The second is what
    /// `shouldPersistAnswers` did, including its special case for a question with no answer yet —
    /// which is just a comparison against the empty answer.
    ///
    /// A slot still owing an upload always warrants a save, without comparison: it is new by
    /// definition. That replaces the `allowEmpty` flag the old cache method needed.
    func plan(
        for draft: AnswerDraft,
        baseline: NormalizedAnswer,
        questionId: String,
        in host: any AnswerDraftHost
    ) -> AnswerSavePlan? {
        guard draft.hasChanges(against: baseline) else { return nil }

        let optimistic = draft.normalized()
        let previous = host.currentAnswer(for: questionId)
        let uploads = draft.pendingUploads

        guard !uploads.isEmpty || optimistic != (previous.map(NormalizedAnswer.init) ?? .empty) else {
            return nil
        }

        return AnswerSavePlan(
            questionId: questionId,
            baseline: baseline,
            previous: previous,
            optimistic: optimistic,
            uploads: uploads
        )
    }

    /// Shows the answer as saved before it is.
    func applyOptimistically(_ plan: AnswerSavePlan, in host: any AnswerDraftHost) {
        host.cache(plan.optimistic, for: plan.questionId)
    }

    /// Persists the answer, uploads any images, then reconciles the URLs that arrived.
    func finish(_ plan: AnswerSavePlan, in host: any AnswerDraftHost) async {
        do {
            try await persister?.save(plan.optimistic, for: plan.questionId)
        } catch {
            // Both paths roll back here. Before AD-2 only the no-image path did, so a failed save
            // with a pending image left the answer looking stored locally while the backend never
            // received it.
            rollBack(plan, in: host)
            host.report(.textSaveFailed)
            return
        }

        guard !plan.uploads.isEmpty else {
            await deleteRemovedImages(plan, finalURLs: plan.optimistic.urls)
            return
        }

        let outcomes = await upload(plan)
        let settled = plan.optimistic.applying(outcomes)

        // Compare and swap. A newer edit may own the cache by now, in which case these URLs describe
        // an answer the user has already replaced and writing them would resurrect it.
        guard cachedAnswer(for: plan, in: host) == plan.optimistic else { return }

        host.cache(settled, for: plan.questionId)

        do {
            try await persister?.save(settled, for: plan.questionId)
        } catch {
            // The text is stored; only the URLs failed. Undo the cache — and the uploads
            // themselves: nothing will reference those files once the cache reads as it did
            // before this attempt, so leaving them in Storage would orphan them permanently.
            host.cache(plan.optimistic, for: plan.questionId)
            await deleteUploaded(outcomes, for: plan.questionId)
            host.report(.imageURLSaveFailed)
            return
        }

        if let failure = outcomes.compactMap(\.failure).first {
            host.report(
                .imageUploadFailed(
                    slotIndex: failure.slotIndex,
                    underlyingDescription: failure.error.localizedDescription
                )
            )
        }

        await deleteRemovedImages(plan, finalURLs: settled.urls)
    }

    // MARK: - Phases

    /// Uploads every pending slot concurrently.
    ///
    /// Outcomes never throw, so one slot failing neither cancels the others nor discards the URLs
    /// that did arrive.
    private func upload(_ plan: AnswerSavePlan) async -> [AnswerImageUploadOutcome] {
        let images = images
        let questionId = plan.questionId

        return await withTaskGroup(of: AnswerImageUploadOutcome.self) { group in
            for upload in plan.uploads {
                group.addTask { await images.upload(upload, questionId: questionId) }
            }

            var outcomes: [AnswerImageUploadOutcome] = []
            for await outcome in group {
                outcomes.append(outcome)
            }
            return outcomes
        }
    }

    /// Removes images the answer no longer refers to. Best effort — a leftover file is not worth
    /// failing a save that otherwise succeeded.
    private func deleteRemovedImages(_ plan: AnswerSavePlan, finalURLs: [String?]) async {
        let images = images

        for index in 0 ..< AnswerDraft.slotCount
            where plan.baseline.urls[index] != nil && finalURLs[index] == nil {
            try? await images.deleteAnswerImage(questionId: plan.questionId, slotIndex: index)
        }
    }

    /// Deletes every slot this attempt uploaded. Called only when the follow-up URL save fails:
    /// the cache has already rolled back to a state with no URL for these slots, so nothing will
    /// ever reference the file again. Best effort, for the same reason as `deleteRemovedImages`.
    private func deleteUploaded(_ outcomes: [AnswerImageUploadOutcome], for questionId: String) async {
        let images = images

        for case let .uploaded(slotIndex, _, _) in outcomes {
            try? await images.deleteAnswerImage(questionId: questionId, slotIndex: slotIndex)
        }
    }

    /// Undoes the optimistic write, but only if it is still the thing in the cache.
    private func rollBack(_ plan: AnswerSavePlan, in host: any AnswerDraftHost) {
        guard cachedAnswer(for: plan, in: host) == plan.optimistic else { return }
        host.restore(plan.previous, for: plan.questionId)
    }

    private func cachedAnswer(
        for plan: AnswerSavePlan,
        in host: any AnswerDraftHost
    ) -> NormalizedAnswer? {
        host.currentAnswer(for: plan.questionId).map(NormalizedAnswer.init)
    }
}

// MARK: - Injection

private struct AnswerDraftStoreKey: EnvironmentKey {
    /// A default rather than an `@EnvironmentObject`, deliberately.
    ///
    /// Nothing observes this store, so it needs no publishing — and an environment object would have
    /// to be added to all seven UI-test harness roots, where forgetting one is a runtime crash rather
    /// than a compile error. AD-1 paid exactly that tax for `FavoriteStore` across six of them.
    ///
    /// Cache-only, and deliberately so. The app installs its own store through
    /// `appEnvironment(_:)`, so this is what a screen gets when nothing wired it — an editor that
    /// still edits, and a save that reaches no backend. The default cannot be the live store: a
    /// harness that forgot the modifier would then write to Firestore, which is the direction
    /// `docs/adr/0005` argues against.
    ///
    /// Built lazily, so a screen that never saves an answer never constructs a Firebase client.
    static let defaultValue = AnswerDraftStore(
        persister: nil,
        images: LiveAnswerImageStore(suggestionService: nil)
    )
}

extension EnvironmentValues {
    /// The answer-draft store. Override in tests and previews; production reads the default.
    var answerDraftStore: AnswerDraftStore {
        get { self[AnswerDraftStoreKey.self] }
        set { self[AnswerDraftStoreKey.self] = newValue }
    }
}
