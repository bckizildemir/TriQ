import Foundation
import Testing
import UIKit
@testable import TTB

/// Account deletion runs all data deletion in one server callable, then deletes the Auth user
/// last (TriQ#88). These cover what happens around that callable with a mock in its place.
@Suite(.timeLimit(.minutes(1)))
struct AccountDeletionServerStepTests {
    private static let downloadURL =
        "https://firebasestorage.googleapis.com/v0/b/test/o/profiles%2Fanon-1%2Fprofile.jpg?alt=media&token=t"

    private static func anonymousService(
        operations: MockAccountDeletionOperations,
        imageService: ImageService = ImageService()
    ) -> AccountDeletionService {
        AccountDeletionService(
            operations: operations,
            auth: MockAccountDeletionAuth(
                currentUserValue: MockAccountDeletionUser(uid: "anon-1", isAnonymous: true, email: nil)
            ),
            imageService: imageService
        )
    }

    @Test func callableFailureKeepsTheAuthUser() async {
        let operations = MockAccountDeletionOperations()
        operations.failures["deleteAccountData"] = AccountDeletionError.dataDeletionFailed
        let service = Self.anonymousService(operations: operations)

        await #expect(throws: AccountDeletionError.dataDeletionFailed) {
            try await service.deleteCurrentAccount(password: nil)
        }

        #expect(operations.callLog == ["deleteAccountData"])
    }

    @Test func retryAfterAFailureRunsTheCallableAgainAndDeletesTheAuthUser() async throws {
        let operations = MockAccountDeletionOperations()
        operations.failures["deleteAccountData"] = AccountDeletionError.dataDeletionFailed
        let service = Self.anonymousService(operations: operations)
        _ = try? await service.deleteCurrentAccount(password: nil)

        operations.failures = [:]
        try await service.deleteCurrentAccount(password: nil)

        #expect(operations.callLog == [
            "deleteAccountData",
            "deleteAccountData",
            "deleteLocalProfileImage",
            "deleteAuthUser",
        ])
    }

    /// The server deletes the photo from Storage, so the in-memory copy under its download URL
    /// must go too (#85).
    @Test func successEvictsTheCachedProfilePhoto() async throws {
        let operations = MockAccountDeletionOperations()
        operations.summary = AccountDeletionSummary(profileImageURL: Self.downloadURL)
        let imageService = ImageService()
        await imageService.cacheImage(Self.solidImage(), for: Self.downloadURL)
        let service = Self.anonymousService(operations: operations, imageService: imageService)

        try await service.deleteCurrentAccount(password: nil)

        #expect(await imageService.cachedImage(for: Self.downloadURL) == nil)
    }

    @Test func failureKeepsTheCachedProfilePhoto() async {
        let operations = MockAccountDeletionOperations()
        operations.summary = AccountDeletionSummary(profileImageURL: Self.downloadURL)
        operations.failures["deleteAccountData"] = AccountDeletionError.dataDeletionFailed
        let imageService = ImageService()
        await imageService.cacheImage(Self.solidImage(), for: Self.downloadURL)
        let service = Self.anonymousService(operations: operations, imageService: imageService)

        _ = try? await service.deleteCurrentAccount(password: nil)

        #expect(await imageService.cachedImage(for: Self.downloadURL) != nil)
    }

    private static func solidImage() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        }
    }
}
