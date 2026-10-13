import Foundation

/// Where the profile photo comes from, read from the user document's `profileImageURL` (#71).
enum ProfilePhotoSource: Equatable {
    /// A download URL in Firebase Storage.
    case remote(String)
    /// The user removed the photo: the field holds `""`. The local copy must not come back.
    case removed
    /// No field: a legacy account that saved the photo on this device only.
    case legacyLocal

    /// The removal writes `""` rather than deleting the field, because the Firestore rules accept
    /// only a string there. So an empty string means "no photo", wherever the field is read.
    init(storedValue: Any?) {
        guard let urlString = storedValue as? String else {
            self = .legacyLocal
            return
        }
        self = urlString.isEmpty ? .removed : .remote(urlString)
    }
}
