import FirebaseFirestore
import Foundation

/// Removes the signed-in user's profile photo from the backend (#71), in two steps, so the model
/// can drop the local copy as soon as the Storage file is gone, even if the second step fails.
protocol ProfilePhotoRemoving: Sendable {
    /// Deletes `profiles/{userId}/profile.jpg`. A file that is already gone counts as deleted.
    /// - Parameter downloadURL: the URL the photo was loaded from, so its in-memory cache entry
    ///   goes too; `nil` when the model never had one.
    func deleteStoredPhoto(userId: String, downloadURL: String?) async throws

    /// Writes `profileImageURL: ""` and `hasProfilePicture: false` to `users/{userId}`.
    func clearPhotoFields(userId: String) async throws
}

/// The live adapter. Its two SDK calls run in no test; `clearedUserFields()` and
/// `ImageService.isMissingStorageObject(_:)` hold its logic and are tested.
struct LiveProfilePhotoRemover: ProfilePhotoRemoving {
    func deleteStoredPhoto(userId: String, downloadURL: String?) async throws {
        do {
            try await ImageService.shared.deleteProfileImage(userId: userId, downloadURL: downloadURL)
        } catch where ImageService.isMissingStorageObject(error) {
            // Already gone, for example after a removal whose Firestore write failed: the retry
            // goes on to clear the fields.
        }
    }

    func clearPhotoFields(userId: String) async throws {
        try await Firestore.firestore().collection("users").document(userId)
            .updateData(Self.clearedUserFields())
    }

    /// `""`, not `null` or a deleted key: the Firestore rules accept only a string for
    /// `profileImageURL`. Readers treat `""` as "no photo" (`ProfilePhotoSource`).
    static func clearedUserFields() -> [String: Any] {
        [
            "profileImageURL": "",
            "hasProfilePicture": false,
            "updatedAt": FieldValue.serverTimestamp(),
        ]
    }
}
