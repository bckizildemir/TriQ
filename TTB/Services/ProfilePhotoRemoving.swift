import FirebaseFirestore
import Foundation

/// Removes the signed-in user's profile photo from the backend (#71).
protocol ProfilePhotoRemoving: Sendable {
    /// Deletes the Storage file and clears the photo fields of `users/{userId}`.
    /// - Parameter downloadURL: the URL the photo was loaded from, so its in-memory cache entry
    ///   goes too; `nil` when the model never had one.
    func removeProfilePhoto(userId: String, downloadURL: String?) async throws
}

/// The live adapter. Its two SDK calls run in no test; `clearedUserFields()` and
/// `ImageService.isMissingStorageObject(_:)` hold its logic and are tested.
struct LiveProfilePhotoRemover: ProfilePhotoRemoving {
    func removeProfilePhoto(userId: String, downloadURL: String?) async throws {
        do {
            try await ImageService.shared.deleteProfileImage(downloadURL: downloadURL)
        } catch where ImageService.isMissingStorageObject(error) {
            // Already gone, for example after a removal whose Firestore write failed: clear the
            // fields anyway, so the retry succeeds.
        }
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
