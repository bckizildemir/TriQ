import Foundation
@testable import TTB

/// Records each removal request and fails with `error` when one is set.
actor FakeProfilePhotoRemover: ProfilePhotoRemoving {
    struct Call: Equatable {
        let userId: String
        let downloadURL: String?
    }

    private(set) var calls: [Call] = []
    private let error: (any Error)?

    init(error: (any Error)? = nil) {
        self.error = error
    }

    func removeProfilePhoto(userId: String, downloadURL: String?) async throws {
        calls.append(Call(userId: userId, downloadURL: downloadURL))
        if let error {
            throw error
        }
    }
}
