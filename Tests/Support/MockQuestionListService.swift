import FirebaseFirestore
import Foundation
@testable import TTB

final class MockQuestionListListenerRegistration: NSObject, ListenerRegistration {
    private(set) var isRemoved = false

    func remove() {
        isRemoved = true
    }
}

actor MockQuestionListService: QuestionListServicing {
    enum MockError: Error {
        case updateFailed
        case deleteFailed
    }

    private var blockedUpdateListIDs: Set<String> = []
    private var failingUpdateListIDs: Set<String> = []
    private var updateContinuations: [
        String: [CheckedContinuation<Void, Never>]
    ] = [:]
    private var updateStartedListIDs: Set<String> = []
    private var updateStartedContinuations: [String: CheckedContinuation<Void, Never>] = [:]
    private var blockedDeleteListIDs: Set<String> = []
    private var failingDeleteListIDs: Set<String> = []
    private var deleteContinuations: [String: CheckedContinuation<Void, Never>] = [:]
    private var deleteStartedListIDs: Set<String> = []
    private var deleteStartedContinuations: [String: CheckedContinuation<Void, Never>] = [:]
    private var listenerCompletions: [
        String: (Result<[QuestionList], Error>) -> Void
    ] = [:]
    private var startedListenerUserIDs: Set<String> = []
    private var listenerStartedContinuations: [
        String: CheckedContinuation<Void, Never>
    ] = [:]
    private var blockedCreateOwnerIDs: Set<String> = []
    private var createResultsByOwnerID: [String: String] = [:]
    private var createContinuations: [String: CheckedContinuation<Void, Never>] = [:]
    private var createStartedOwnerIDs: Set<String> = []
    private var createStartedContinuations: [
        String: CheckedContinuation<Void, Never>
    ] = [:]
    private var blockedSetQuestionListIDs: Set<String> = []
    private var setQuestionContinuations: [
        String: [CheckedContinuation<Void, Never>]
    ] = [:]
    private var setQuestionCallsByListID: [String: [Bool]] = [:]
    private var setQuestionCallCountContinuations: [
        SetQuestionCallTarget: CheckedContinuation<Void, Never>
    ] = [:]

    func setupQuestionListsListener(
        userId: String,
        completion: @escaping (Result<[QuestionList], Error>) -> Void
    ) async -> ListenerRegistration {
        listenerCompletions[userId] = completion
        startedListenerUserIDs.insert(userId)
        listenerStartedContinuations.removeValue(forKey: userId)?.resume()
        return MockQuestionListListenerRegistration()
    }

    func createList(named name: String, ownerId: String) async throws -> String {
        _ = name
        createStartedOwnerIDs.insert(ownerId)
        createStartedContinuations.removeValue(forKey: ownerId)?.resume()
        if blockedCreateOwnerIDs.contains(ownerId) {
            await withCheckedContinuation { continuation in
                createContinuations[ownerId] = continuation
            }
        }
        return createResultsByOwnerID[ownerId] ?? UUID().uuidString
    }

    func updateList(listId: String, name: String) async throws {
        _ = name
        updateStartedListIDs.insert(listId)
        updateStartedContinuations.removeValue(forKey: listId)?.resume()

        if blockedUpdateListIDs.contains(listId) {
            await withCheckedContinuation { continuation in
                updateContinuations[listId, default: []].append(continuation)
            }
        }

        if failingUpdateListIDs.contains(listId) {
            throw MockError.updateFailed
        }
    }

    func deleteList(listId: String) async throws {
        deleteStartedListIDs.insert(listId)
        deleteStartedContinuations.removeValue(forKey: listId)?.resume()

        if blockedDeleteListIDs.contains(listId) {
            await withCheckedContinuation { continuation in
                deleteContinuations[listId] = continuation
            }
        }

        if failingDeleteListIDs.contains(listId) {
            throw MockError.deleteFailed
        }
    }

    func setQuestion(
        _ questionId: String,
        in listId: String,
        isIncluded: Bool
    ) async throws {
        _ = questionId
        setQuestionCallsByListID[listId, default: []].append(isIncluded)
        let callCount = setQuestionCallsByListID[listId]?.count ?? 0
        let reachedTargets = setQuestionCallCountContinuations.keys.filter {
            $0.listID == listId && $0.count <= callCount
        }
        for target in reachedTargets {
            setQuestionCallCountContinuations.removeValue(forKey: target)?.resume()
        }

        if blockedSetQuestionListIDs.contains(listId) {
            await withCheckedContinuation { continuation in
                setQuestionContinuations[listId, default: []].append(continuation)
            }
        }
    }

    func blockUpdate(for listId: String, failsWhenResumed: Bool) {
        blockedUpdateListIDs.insert(listId)
        if failsWhenResumed {
            failingUpdateListIDs.insert(listId)
        }
    }

    func waitUntilUpdateStarts(for listId: String) async {
        guard !updateStartedListIDs.contains(listId) else { return }
        await withCheckedContinuation { continuation in
            updateStartedContinuations[listId] = continuation
        }
    }

    func resumeUpdate(for listId: String) {
        blockedUpdateListIDs.remove(listId)
        let continuations = updateContinuations.removeValue(forKey: listId) ?? []
        for continuation in continuations {
            continuation.resume()
        }
    }

    func blockDelete(for listId: String, failsWhenResumed: Bool) {
        blockedDeleteListIDs.insert(listId)
        if failsWhenResumed {
            failingDeleteListIDs.insert(listId)
        }
    }

    func waitUntilDeleteStarts(for listId: String) async {
        guard !deleteStartedListIDs.contains(listId) else { return }
        await withCheckedContinuation { continuation in
            deleteStartedContinuations[listId] = continuation
        }
    }

    func resumeDelete(for listId: String) {
        blockedDeleteListIDs.remove(listId)
        deleteContinuations.removeValue(forKey: listId)?.resume()
    }

    func waitUntilListenerStarts(for userId: String) async {
        guard !startedListenerUserIDs.contains(userId) else { return }
        await withCheckedContinuation { continuation in
            listenerStartedContinuations[userId] = continuation
        }
    }

    func sendSnapshot(_ lists: [QuestionList], for userId: String) {
        listenerCompletions[userId]?(.success(lists))
    }

    func blockCreate(for ownerID: String, returning listID: String) {
        blockedCreateOwnerIDs.insert(ownerID)
        createResultsByOwnerID[ownerID] = listID
    }

    func waitUntilCreateStarts(for ownerID: String) async {
        guard !createStartedOwnerIDs.contains(ownerID) else { return }
        await withCheckedContinuation { continuation in
            createStartedContinuations[ownerID] = continuation
        }
    }

    func resumeCreate(for ownerID: String) {
        blockedCreateOwnerIDs.remove(ownerID)
        createContinuations.removeValue(forKey: ownerID)?.resume()
    }

    func blockSetQuestion(for listID: String) {
        blockedSetQuestionListIDs.insert(listID)
    }

    func waitUntilSetQuestionCallCount(_ count: Int, for listID: String) async {
        guard (setQuestionCallsByListID[listID]?.count ?? 0) < count else { return }
        await withCheckedContinuation { continuation in
            setQuestionCallCountContinuations[
                SetQuestionCallTarget(listID: listID, count: count)
            ] = continuation
        }
    }

    func setQuestionInclusionValues(for listID: String) -> [Bool] {
        setQuestionCallsByListID[listID] ?? []
    }

    func resumeSetQuestion(for listID: String) {
        blockedSetQuestionListIDs.remove(listID)
        let continuations = setQuestionContinuations.removeValue(forKey: listID) ?? []
        for continuation in continuations {
            continuation.resume()
        }
    }
}

private struct SetQuestionCallTarget: Hashable {
    let listID: String
    let count: Int
}
