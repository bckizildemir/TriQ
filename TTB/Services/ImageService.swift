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

    // In-memory cache keyed by download URL
    private let cache = NSCache<NSString, UIImage>()
    // Deduplicate concurrent uploads targeting the same storage path.
    private var inFlightUploads: [String: Task<String, Error>] = [:]

    /// Internal, not private, so a test can build a fresh instance with an empty cache.
    init() {
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
        let ref = Storage.storage().reference().child(path)
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
        let ref = Storage.storage().reference().child(path)
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
            let (data, _) = try await URLSession.shared.data(for: Self.profileImageRequest(for: url))
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

    /// The fixed Storage path keeps one download URL across uploads, so a response that
    /// `URLCache` stored for the old photo would match the new one. `cache` already holds the
    /// photo for this run; the download only runs on a cache miss, such as after a relaunch.
    static func profileImageRequest(for url: URL) -> URLRequest {
        URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
    }

    private func profileImagePath(userId: String) -> String {
        "profiles/\(userId)/profile.jpg"
    }

    // MARK: - Load from cache

    /// Returns a cached UIImage for the given key if available.
    func cachedImage(for key: String) -> UIImage? {
        cache.object(forKey: key as NSString)
    }

    /// Stores a downloaded UIImage in the cache.
    ///
    /// The cost matters: `NSCache` only enforces `totalCostLimit` for entries whose cost the caller
    /// supplies. Inserting without one left `countLimit = 60` as the only bound, which for
    /// full-resolution bitmaps is gigabytes rather than the intended 60 MB.
    func cacheImage(_ image: UIImage, for key: String) {
        cache.setObject(
            image,
            forKey: key as NSString,
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
                let ref = Storage.storage().reference().child(path)
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
        storeUploadedImage(image, downloadURL: url)
        return url
    }

    /// Caches what was actually uploaded, not the larger original the caller handed in.
    ///
    /// The key is the download URL, the key `loadProfileImage(from:)` reads. A fixed path such as
    /// `profiles/<uid>/profile.jpg` keeps its URL across uploads, so an entry keyed by path left
    /// the old photo under the URL key, and the next load by URL returned it (#70).
    func storeUploadedImage(_ image: UIImage, downloadURL: String) {
        cacheImage(Self.resizeIfNeeded(image, maxDimension: Self.uploadMaxDimension), for: downloadURL)
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
