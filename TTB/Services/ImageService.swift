import UIKit
import FirebaseStorage
import FirebaseAuth

// MARK: - ImageService Errors

enum ImageServiceError: LocalizedError {
    case notAuthenticated
    case compressionFailed
    case uploadFailed(Error)
    case downloadFailed(Error)
    case deleteFailed(Error)
    case invalidURL

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return AppLocalization.prefersEnglish
                ? "You need to sign in before uploading an image."
                : "Görsel yüklemek için giriş yapmalısınız."
        case .compressionFailed:
            return AppLocalization.prefersEnglish ? "The image could not be processed." : "Görsel işlenemedi."
        case .uploadFailed(let error):
            return AppLocalization.prefersEnglish
                ? "The image could not be uploaded: \(error.localizedDescription)"
                : "Görsel yüklenemedi: \(error.localizedDescription)"
        case .downloadFailed(let error):
            return AppLocalization.prefersEnglish
                ? "The image could not be downloaded: \(error.localizedDescription)"
                : "Görsel indirilemedi: \(error.localizedDescription)"
        case .deleteFailed(let error):
            return AppLocalization.prefersEnglish
                ? "The image could not be deleted: \(error.localizedDescription)"
                : "Görsel silinemedi: \(error.localizedDescription)"
        case .invalidURL:
            return AppLocalization.prefersEnglish ? "The image URL is invalid." : "Geçersiz görsel URL'si."
        }
    }
}

// MARK: - ImageService

actor ImageService {
    static let shared = ImageService()

    private let storage = Storage.storage()
    // In-memory cache keyed by storage path
    private let cache = NSCache<NSString, UIImage>()
    // Deduplicate concurrent uploads targeting the same storage path.
    private var inFlightUploads: [String: Task<String, Error>] = [:]

    private init() {
        cache.countLimit = 60
        cache.totalCostLimit = 60 * 1024 * 1024 // 60MB
    }

    // MARK: - Upload

    /// Compresses and uploads a UIImage to Firebase Storage.
    /// Returns the https download URL string.
    func uploadAnswerImage(
        _ image: UIImage,
        questionId: String,
        slotIndex: Int
    ) async throws -> String {
        guard let userId = Auth.auth().currentUser?.uid else {
            throw ImageServiceError.notAuthenticated
        }

        let path = storagePath(userId: userId, questionId: questionId, slotIndex: slotIndex)
        return try await uploadImage(image, to: path)
    }

    // MARK: - Delete

    /// Deletes an answer image from Firebase Storage.
    func deleteAnswerImage(questionId: String, slotIndex: Int) async throws {
        guard let userId = Auth.auth().currentUser?.uid else {
            throw ImageServiceError.notAuthenticated
        }
        let path = storagePath(userId: userId, questionId: questionId, slotIndex: slotIndex)
        let ref = storage.reference().child(path)
        cache.removeObject(forKey: path as NSString)
        do {
            try await ref.delete()
        } catch {
            throw ImageServiceError.deleteFailed(error)
        }
    }

    /// Deletes all answer images for a question (all slots).
    func deleteAllAnswerImages(questionId: String) async {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        for index in 0..<3 {
            try? await deleteAnswerImage(questionId: questionId, slotIndex: index)
            _ = userId // suppress warning
        }
    }

    // MARK: - Profile Image

    /// Compresses and uploads a profile UIImage to Firebase Storage.
    /// Returns the https download URL string.
    func uploadProfileImage(_ image: UIImage) async throws -> String {
        guard let userId = Auth.auth().currentUser?.uid else {
            throw ImageServiceError.notAuthenticated
        }

        let path = profileImagePath(userId: userId)
        return try await uploadImage(image, to: path)
    }

    /// Deletes the current user's profile image from Firebase Storage.
    func deleteProfileImage() async throws {
        guard let userId = Auth.auth().currentUser?.uid else {
            throw ImageServiceError.notAuthenticated
        }
        let path = profileImagePath(userId: userId)
        let ref = storage.reference().child(path)
        cache.removeObject(forKey: path as NSString)
        do {
            try await ref.delete()
        } catch {
            throw ImageServiceError.deleteFailed(error)
        }
    }

    /// Downloads a profile image from a Firebase Storage URL string.
    /// Returns cached image if available.
    func loadProfileImage(from urlString: String) async throws -> UIImage {
        if let cached = cache.object(forKey: urlString as NSString) {
            return cached
        }

        guard let url = URL(string: urlString) else {
            throw ImageServiceError.invalidURL
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            // Downsampled decode: uploads are capped at 800 px, but legacy profile photos predate
            // that cap and would otherwise decode at their original size.
            guard let image = DownsampledImageDecoder.image(from: data) ?? UIImage(data: data) else {
                throw ImageServiceError.downloadFailed(NSError(domain: "ImageService", code: -1,
                    userInfo: [NSLocalizedDescriptionKey: AppLocalization.prefersEnglish
                        ? "Could not decode image data"
                        : "Görsel verisi çözülemedi"]))
            }
            cacheImage(image, for: urlString)
            return image
        } catch let error as ImageServiceError {
            throw error
        } catch {
            throw ImageServiceError.downloadFailed(error)
        }
    }

    private func profileImagePath(userId: String) -> String {
        "profiles/\(userId)/profile.jpg"
    }

    // MARK: - Load from cache

    /// Returns a cached UIImage for the given path if available.
    func cachedImage(for path: String) -> UIImage? {
        cache.object(forKey: path as NSString)
    }

    /// Stores a downloaded UIImage in the cache.
    ///
    /// The cost matters: `NSCache` only enforces `totalCostLimit` for entries whose cost the caller
    /// supplies. Inserting without one left `countLimit = 60` as the only bound, which for
    /// full-resolution bitmaps is gigabytes rather than the intended 60 MB.
    func cacheImage(_ image: UIImage, for path: String) {
        cache.setObject(
            image,
            forKey: path as NSString,
            cost: DownsampledImageDecoder.decodedByteCost(of: image)
        )
    }

    // MARK: - Helpers

    private func storagePath(userId: String, questionId: String, slotIndex: Int) -> String {
        "answers/\(userId)/\(questionId)/slot_\(slotIndex).jpg"
    }

    private func uploadImage(_ image: UIImage, to path: String) async throws -> String {
        if let existingTask = inFlightUploads[path] {
            return try await existingTask.value
        }

        let uploadTask = Task<String, Error> {
            do {
                let compressed = try Self.compressImage(image)
                let ref = self.storage.reference().child(path)
                let metadata = StorageMetadata()
                metadata.contentType = "image/jpeg"

                _ = try await ref.putDataAsync(compressed, metadata: metadata)
                let url = try await ref.downloadURL()
                return url.absoluteString
            } catch {
                throw ImageServiceError.uploadFailed(error)
            }
        }

        inFlightUploads[path] = uploadTask
        defer { inFlightUploads.removeValue(forKey: path) }

        let url = try await uploadTask.value
        // Cache what was actually uploaded, not the larger original the caller handed in.
        cacheImage(Self.resizeIfNeeded(image, maxDimension: Self.uploadMaxDimension), for: path)
        return url
    }

    /// Longest-edge cap applied to every upload.
    static let uploadMaxDimension: CGFloat = 800

    private static func compressImage(_ image: UIImage) throws -> Data {
        let resized = resizeIfNeeded(image, maxDimension: uploadMaxDimension)
        guard let data = resized.jpegData(compressionQuality: 0.60) else {
            throw ImageServiceError.compressionFailed
        }
        return data
    }

    private static func resizeIfNeeded(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        let longestSide = max(size.width, size.height)
        guard longestSide > maxDimension else { return image }

        let scale = maxDimension / longestSide
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)

        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}

// MARK: - StorageReference async helpers (backfill for SDK versions without native async)

extension StorageReference {
    func putDataAsync(_ data: Data, metadata: StorageMetadata?) async throws -> StorageMetadata {
        try await withCheckedThrowingContinuation { continuation in
            var resumed = false
            let task = putData(data, metadata: metadata) { meta, error in
                guard !resumed else { return }
                resumed = true

                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: meta ?? StorageMetadata())
                }
            }

            _ = task
        }
    }
}
