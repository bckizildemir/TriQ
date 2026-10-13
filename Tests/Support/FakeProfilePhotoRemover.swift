import Foundation
@testable import TTB

/// Records each step of a removal and fails a step when its error is set. With
/// `suspendsDelete`, the Storage step waits until the test calls `resumeDelete()`, so a test can
/// change the signed-in user while the removal is in flight.
actor FakeProfilePhotoRemover: ProfilePhotoRemoving {
    enum Call: Equatable {
        case deleteStoredPhoto(userId: String, downloadURL: String?)
        case clearPhotoFields(userId: String)
    }

    private(set) var calls: [Call] = []
    private let deleteError: (any Error)?
    private let clearError: (any Error)?
    private let suspendsDelete: Bool
    private var deleteContinuation: CheckedContinuation<Void, Never>?
    private var suspendedWaiters: [CheckedContinuation<Void, Never>] = []

    init(
        deleteError: (any Error)? = nil,
        clearError: (any Error)? = nil,
        suspendsDelete: Bool = false
    ) {
        self.deleteError = deleteError
        self.clearError = clearError
        self.suspendsDelete = suspendsDelete
    }

    func deleteStoredPhoto(userId: String, downloadURL: String?) async throws {
        calls.append(.deleteStoredPhoto(userId: userId, downloadURL: downloadURL))
        if suspendsDelete {
            await withCheckedContinuation { continuation in
                deleteContinuation = continuation
                suspendedWaiters.forEach { $0.resume() }
                suspendedWaiters.removeAll()
            }
        }
        if let deleteError {
            throw deleteError
        }
    }

    func clearPhotoFields(userId: String) async throws {
        calls.append(.clearPhotoFields(userId: userId))
        if let clearError {
            throw clearError
        }
    }

    /// Returns once the Storage step is suspended.
    func waitUntilDeleteIsSuspended() async {
        guard deleteContinuation == nil else { return }
        await withCheckedContinuation { suspendedWaiters.append($0) }
    }

    func resumeDelete() {
        deleteContinuation?.resume()
        deleteContinuation = nil
    }
}
