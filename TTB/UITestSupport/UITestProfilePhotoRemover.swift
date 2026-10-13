import Foundation

#if DEBUG
/// Lets the profile harness remove its fixture photo without Firebase.
struct UITestProfilePhotoRemover: ProfilePhotoRemoving {
    func removeProfilePhoto(userId: String, downloadURL: String?) async throws {}
}
#endif
