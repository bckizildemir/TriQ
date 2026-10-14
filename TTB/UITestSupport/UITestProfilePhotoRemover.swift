import Foundation

#if DEBUG
/// Lets the profile harness remove its fixture photo without Firebase.
struct UITestProfilePhotoRemover: ProfilePhotoRemoving {
    func deleteStoredPhoto(userId: String, downloadURL: String?) async throws {}
    func clearPhotoFields(userId: String) async throws {}
}
#endif
