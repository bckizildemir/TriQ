import ImageIO
import UIKit
import UniformTypeIdentifiers

/// Decodes picked photo data straight to the size the app actually needs.
///
/// A decoded bitmap costs `width × height × 4` bytes of backing store no matter how small the file
/// is, so `UIImage(data:)` on a camera photo materializes ~48 MB for 12 MP and ~195 MB for 48 MP.
/// Every one of those photos is uploaded at 800 px and displayed no larger than the screen, so the
/// full-resolution bitmap is never needed. `CGImageSourceCreateThumbnailAtIndex` with
/// `kCGImageSourceThumbnailMaxPixelSize` decodes at the target size without materializing the
/// original first.
enum DownsampledImageDecoder {
    /// Longest-edge cap for photos picked for a profile or an answer slot.
    ///
    /// Sized from what the app does with them: `ImageService` compresses every upload to 800 px, and
    /// the largest on-screen presentation is a full-screen `scaledToFit` viewer. 1024 leaves headroom
    /// above the upload cap while costing 4 MB resident instead of 48 MB.
    static let pickedPhotoMaxPixelSize = 1024

    /// Decodes `data` with its longest edge no larger than `maxPixelSize`, honouring EXIF
    /// orientation. Returns `nil` when the data is not a decodable image.
    static func image(from data: Data, maxPixelSize: Int = pickedPhotoMaxPixelSize) -> UIImage? {
        guard maxPixelSize > 0,
              let source = CGImageSourceCreateWithData(
                  data as CFData,
                  [kCGImageSourceShouldCache: false] as CFDictionary
              )
        else { return nil }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(
            source, 0, options as CFDictionary
        ) else { return nil }

        return UIImage(cgImage: cgImage)
    }

    /// The resident cost of an image's decoded bitmap, for `NSCache.totalCostLimit` accounting.
    static func decodedByteCost(of image: UIImage) -> Int {
        if let cgImage = image.cgImage {
            return cgImage.bytesPerRow * cgImage.height
        }
        let pixelWidth = image.size.width * image.scale
        let pixelHeight = image.size.height * image.scale
        return Int((pixelWidth * pixelHeight * 4).rounded(.up))
    }

    /// The first registered type identifier that is an image, for `NSItemProvider` data loading.
    /// The provider registers concrete types (`public.heic`, `public.jpeg`), so asking it for
    /// `public.image` directly can fail.
    static func imageTypeIdentifier(in registeredTypeIdentifiers: [String]) -> String? {
        registeredTypeIdentifiers.first { identifier in
            UTType(identifier)?.conforms(to: .image) == true
        }
    }
}
