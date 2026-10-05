import Foundation

struct AnswerImageAttribution: Hashable, Sendable {
    let provider: String
    let photoId: String
    let photographer: String
    let photographerURL: String
    let photoURL: String

    var firestoreValue: [String: Any] {
        [
            "provider": provider,
            "photoId": photoId,
            "photographer": photographer,
            "photographerURL": photographerURL,
            "photoURL": photoURL,
        ]
    }

    init(
        provider: String,
        photoId: String,
        photographer: String,
        photographerURL: String,
        photoURL: String
    ) {
        self.provider = provider
        self.photoId = photoId
        self.photographer = photographer
        self.photographerURL = photographerURL
        self.photoURL = photoURL
    }

    init?(firestoreValue: Any) {
        guard let data = firestoreValue as? [String: Any],
              let provider = data["provider"] as? String,
              let photoId = data["photoId"] as? String
        else {
            return nil
        }

        self.provider = provider
        self.photoId = photoId
        photographer = data["photographer"] as? String ?? ""
        photographerURL = data["photographerURL"] as? String ?? ""
        photoURL = data["photoURL"] as? String ?? ""
    }
}

struct AnswerImageSuggestion: Identifiable, Hashable, Sendable {
    let id: String
    let photoId: String
    let thumbnailURL: String
    let previewURL: String
    let fullSizeURL: String
    let photographer: String
    let photographerURL: String
    let photoURL: String

    var thumbnailImageURL: URL? {
        URL(string: thumbnailURL)
    }

    var previewImageURL: URL? {
        URL(string: previewURL)
    }

    var attribution: AnswerImageAttribution {
        AnswerImageAttribution(
            provider: "pexels",
            photoId: photoId,
            photographer: photographer,
            photographerURL: photographerURL,
            photoURL: photoURL
        )
    }

    var functionsPayload: [String: Any] {
        [
            "photoId": photoId,
            "thumbnailURL": thumbnailURL,
            "previewURL": previewURL,
            "fullSizeURL": fullSizeURL,
            "photographer": photographer,
            "photographerURL": photographerURL,
            "photoURL": photoURL,
        ]
    }

    init(
        id: String,
        photoId: String,
        thumbnailURL: String,
        previewURL: String,
        fullSizeURL: String,
        photographer: String,
        photographerURL: String,
        photoURL: String
    ) {
        self.id = id
        self.photoId = photoId
        self.thumbnailURL = thumbnailURL
        self.previewURL = previewURL
        self.fullSizeURL = fullSizeURL
        self.photographer = photographer
        self.photographerURL = photographerURL
        self.photoURL = photoURL
    }

    init?(functionsValue: Any) {
        guard let data = functionsValue as? [String: Any],
              let photoId = data["photoId"] as? String,
              let thumbnailURL = data["thumbnailURL"] as? String,
              let previewURL = data["previewURL"] as? String,
              let fullSizeURL = data["fullSizeURL"] as? String
        else {
            return nil
        }

        let normalizedPhotoID = photoId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            !normalizedPhotoID.isEmpty,
            let normalizedThumbnailURL = Self.normalizedRemoteURL(thumbnailURL),
            let normalizedPreviewURL = Self.normalizedRemoteURL(previewURL),
            let normalizedFullSizeURL = Self.normalizedRemoteURL(fullSizeURL)
        else {
            return nil
        }

        if let rawID = data["id"] {
            guard
                let suppliedID = rawID as? String,
                !suppliedID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else {
                return nil
            }
            id = suppliedID.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            id = normalizedPhotoID
        }
        self.photoId = normalizedPhotoID
        self.thumbnailURL = normalizedThumbnailURL
        self.previewURL = normalizedPreviewURL
        self.fullSizeURL = normalizedFullSizeURL
        photographer = data["photographer"] as? String ?? ""
        photographerURL = data["photographerURL"] as? String ?? ""
        photoURL = data["photoURL"] as? String ?? ""
    }

    private static func normalizedRemoteURL(_ value: String) -> String? {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            let components = URLComponents(string: normalized),
            components.scheme == "https" || components.scheme == "http",
            components.host?.isEmpty == false
        else {
            return nil
        }
        return normalized
    }
}
