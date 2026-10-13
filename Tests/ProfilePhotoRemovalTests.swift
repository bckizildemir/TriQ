import FirebaseStorage
import Foundation
import Testing
import UIKit
@testable import TTB

/// The user can remove the profile photo from Edit Profile (#71). The removal writes `""` to
/// `profileImageURL`, so every reader must treat an empty string as "no photo".
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct ProfilePhotoRemovalTests {
    /// `nonisolated` so the parameterized test's arguments can read it outside the main actor.
    private nonisolated static let downloadURL =
        "https://firebasestorage.googleapis.com/v0/b/test/o/profiles%2Fuser-1%2Fprofile.jpg?alt=media&token=fixed"

    private static func makeModel(
        userId: String,
        photo: UIImage? = solidImage(.red),
        remover: FakeProfilePhotoRemover
    ) -> ProfileModel {
        ProfileModel(
            uiTestUsername: "saved-name",
            email: "saved@example.com",
            statistics: .init(),
            userId: userId,
            profileImage: photo,
            profileImageURL: photo == nil ? nil : downloadURL,
            photoRemover: remover
        )
    }

    /// Home and Profile read the same shared model, so clearing its photo shows the default
    /// avatar on both at once. The backend gets the download URL, the key of the in-memory cache.
    @Test func removingThePhotoClearsItAndPassesTheDownloadURL() async {
        let userId = "remove-photo-\(UUID().uuidString)"
        let remover = FakeProfilePhotoRemover()
        let model = Self.makeModel(userId: userId, remover: remover)

        await model.removeProfilePhoto()

        #expect(model.profileImage == nil)
        #expect(!model.hasProfilePhoto)
        #expect(!model.showingAlert)
        #expect(await remover.calls == [.init(userId: userId, downloadURL: Self.downloadURL)])
    }

    /// The local copy is the fallback when the download fails, so leaving it would bring the
    /// removed photo back on the next launch.
    @Test func removingThePhotoDeletesTheLocalCopy() async throws {
        let userId = "remove-photo-\(UUID().uuidString)"
        try LocalFileManager.shared.saveImage(Self.solidImage(.red), name: "profile_\(userId)")
        let model = Self.makeModel(userId: userId, remover: FakeProfilePhotoRemover())

        await model.removeProfilePhoto()

        #expect(LocalFileManager.shared.loadImage(name: "profile_\(userId)") == nil)
    }

    @Test func failedRemovalKeepsThePhotoAndShowsAnAlert() async {
        let userId = "remove-photo-\(UUID().uuidString)"
        let photo = Self.solidImage(.red)
        let remover = FakeProfilePhotoRemover(error: URLError(.notConnectedToInternet))
        let model = Self.makeModel(userId: userId, photo: photo, remover: remover)

        await model.removeProfilePhoto()

        #expect(model.profileImage === photo)
        #expect(model.showingAlert)
        #expect(!model.alertMessage.isEmpty)
    }

    @Test func removalWithoutAPhotoDoesNothing() async {
        let remover = FakeProfilePhotoRemover()
        let model = Self.makeModel(userId: "remove-photo-none", photo: nil, remover: remover)

        await model.removeProfilePhoto()

        #expect(await remover.calls.isEmpty)
        #expect(!model.showingAlert)
    }

    @Test(arguments: [
        (stored: "" as String?, expected: ProfilePhotoSource.removed),
        (stored: downloadURL, expected: .remote(downloadURL)),
        (stored: nil, expected: .legacyLocal),
    ])
    func storedURLMapsToAPhotoSource(stored: String?, expected: ProfilePhotoSource) {
        #expect(ProfilePhotoSource(storedValue: stored) == expected)
    }

    @Test func aStoredValueThatIsNotAStringFallsBackToTheLocalCopy() {
        #expect(ProfilePhotoSource(storedValue: 42) == .legacyLocal)
    }

    /// The Firestore rules accept `""` for `profileImageURL` and reject `null` or a deleted key.
    @Test func removalClearsTheURLWithAnEmptyString() {
        let fields = LiveProfilePhotoRemover.clearedUserFields()

        #expect(fields["profileImageURL"] as? String == "")
        #expect(fields["hasProfilePicture"] as? Bool == false)
        #expect(fields["updatedAt"] != nil)
    }

    /// A Storage file that is already gone must not block clearing the user document.
    @Test func aMissingStorageObjectCountsAsRemoved() {
        let missing = NSError(domain: StorageErrorDomain, code: StorageErrorCode.objectNotFound.rawValue)
        let denied = NSError(domain: StorageErrorDomain, code: StorageErrorCode.unauthorized.rawValue)

        #expect(ImageService.isMissingStorageObject(missing))
        #expect(ImageService.isMissingStorageObject(ImageServiceError.deleteFailed(missing)))
        #expect(!ImageService.isMissingStorageObject(denied))
        #expect(!ImageService.isMissingStorageObject(ImageServiceError.notAuthenticated))
    }

    private static func solidImage(_ color: UIColor) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).image { context in
            color.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        }
    }
}
