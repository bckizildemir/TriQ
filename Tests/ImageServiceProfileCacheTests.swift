import Testing
import UIKit
@testable import TTB

/// The profile photo lives at one fixed Storage path, so a new upload keeps the same download URL.
/// `loadProfileImage(from:)` reads its cache by that URL, so an upload must replace the URL entry.
@Suite(.timeLimit(.minutes(1)))
struct ImageServiceProfileCacheTests {
    private static let downloadURL =
        "https://firebasestorage.googleapis.com/v0/b/test/o/profiles%2Fuser-1%2Fprofile.jpg?alt=media&token=fixed"

    @Test func loadAfterUploadReturnsTheNewImageForTheSameURL() async throws {
        let service = ImageService()
        let oldImage = Self.solidImage(.red)
        let newImage = Self.solidImage(.blue)
        // The launch load cached the old photo under its download URL.
        await service.cacheImage(oldImage, for: Self.downloadURL)

        await service.storeUploadedImage(newImage, downloadURL: Self.downloadURL)
        let loaded = try await service.loadProfileImage(from: Self.downloadURL)

        #expect(loaded === newImage)
    }

    /// Removing the photo (#71) must drop the entry under its download URL, the key uploads and
    /// loads use, or the removed photo stays in memory until the app quits (#85).
    @Test func evictingTheDownloadURLDropsTheCachedPhoto() async {
        let service = ImageService()
        await service.cacheImage(Self.solidImage(.red), for: Self.downloadURL)

        await service.evictProfileImage(downloadURL: Self.downloadURL)

        #expect(await service.cachedImage(for: Self.downloadURL) == nil)
    }

    /// No reader loads answer images from the cache, so an answer upload must not fill it (#85).
    @Test func answerUploadDoesNotWriteTheCache() async {
        let service = ImageService()
        let url = "https://firebasestorage.googleapis.com/v0/b/test/o/answers%2Fu%2Fq%2Fslot_0.jpg?alt=media"

        await service.finishUpload(of: Self.solidImage(.red), downloadURL: url, cachesResult: false)

        #expect(await service.cachedImage(for: url) == nil)
    }

    @Test func profileUploadWritesTheCacheUnderTheDownloadURL() async {
        let service = ImageService()

        await service.finishUpload(of: Self.solidImage(.red), downloadURL: Self.downloadURL, cachesResult: true)

        #expect(await service.cachedImage(for: Self.downloadURL) != nil)
    }

    /// Account deletion has no photo URL from the caller, so it evicts the one it read (#85).
    @Test func accountDeletionEvictsTheCachedProfilePhoto() async {
        let service = ImageService()
        await service.cacheImage(Self.solidImage(.red), for: Self.downloadURL)
        let operations = LiveAccountDeletionOperations(imageService: service)

        await operations.evictCachedProfilePhoto(downloadURL: Self.downloadURL)

        #expect(await service.cachedImage(for: Self.downloadURL) == nil)
    }

    /// After a relaunch the in-memory cache is empty, so the download decides what Home shows. The
    /// same URL must not come back from `URLCache` with the bytes of the photo it replaced.
    @Test func profileDownloadSkipsTheLocalHTTPCache() throws {
        let url = try #require(URL(string: Self.downloadURL))

        let request = ImageService.profileImageRequest(for: url)

        #expect(request.url == url)
        #expect(request.cachePolicy == .reloadIgnoringLocalCacheData)
    }

    private static func solidImage(_ color: UIColor) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).image { context in
            color.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        }
    }
}
