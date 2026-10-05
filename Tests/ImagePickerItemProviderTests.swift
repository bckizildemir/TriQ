import UIKit
import UniformTypeIdentifiers
import XCTest
@testable import TTB

/// Covers the load path `ImagePicker` uses for photos picked from the library.
///
/// `ImagePicker` asks the item provider for a *data* representation and decodes it downsampled,
/// rather than asking for a `UIImage` (which materializes a full-resolution bitmap — ~48 MB for a
/// 12 MP photo). `PHPickerResult.itemProvider` is an `NSItemProvider`, so constructing one here with
/// real image data exercises the same two steps for real: picking a usable type identifier out of
/// what the provider registered, then loading and decoding that representation.
final class ImagePickerItemProviderTests: XCTestCase {

    func testLoadsDownsampledImageFromJPEGItemProvider() async throws {
        let data = try Self.imageData(width: 3024, height: 4032, type: .jpeg)
        let provider = Self.itemProvider(data: data, type: .jpeg)

        let identifier = try XCTUnwrap(
            DownsampledImageDecoder.imageTypeIdentifier(in: provider.registeredTypeIdentifiers),
            "No image type identifier found among \(provider.registeredTypeIdentifiers)"
        )
        let loaded = try await Self.loadDataRepresentation(from: provider, typeIdentifier: identifier)
        let image = try XCTUnwrap(DownsampledImageDecoder.image(from: loaded))

        let longestEdge = max(image.size.width * image.scale, image.size.height * image.scale)
        XCTAssertLessThanOrEqual(
            longestEdge,
            CGFloat(DownsampledImageDecoder.pickedPhotoMaxPixelSize),
            "Picked photo should be capped at the ingestion size, not decoded at full resolution"
        )
    }

    func testLoadsDownsampledImageFromHEICItemProvider() async throws {
        let data = try Self.imageData(width: 2000, height: 1500, type: .heic)
        let provider = Self.itemProvider(data: data, type: .heic)

        let identifier = try XCTUnwrap(
            DownsampledImageDecoder.imageTypeIdentifier(in: provider.registeredTypeIdentifiers),
            "HEIC provider should expose an image-conforming identifier"
        )
        XCTAssertEqual(identifier, UTType.heic.identifier)

        let loaded = try await Self.loadDataRepresentation(from: provider, typeIdentifier: identifier)
        XCTAssertNotNil(DownsampledImageDecoder.image(from: loaded))
    }

    /// The camera-resolution case the change exists for: confirm the decoded bitmap really is orders
    /// of magnitude smaller than a full-resolution decode of the same data.
    func testDownsampledDecodeIsFarSmallerThanFullDecode() throws {
        let data = try Self.imageData(width: 3024, height: 4032, type: .jpeg)

        let downsampled = try XCTUnwrap(DownsampledImageDecoder.image(from: data))
        let full = try XCTUnwrap(UIImage(data: data))

        let downsampledCost = DownsampledImageDecoder.decodedByteCost(of: downsampled)
        let fullCost = DownsampledImageDecoder.decodedByteCost(of: full)

        XCTAssertGreaterThan(fullCost, 40_000_000, "A 12 MP bitmap should be ~48 MB")
        XCTAssertLessThan(downsampledCost, 6_000_000, "A 1024 px bitmap should be ~4 MB")
        XCTAssertGreaterThan(Double(fullCost) / Double(downsampledCost), 8)
    }

    // MARK: - Helpers

    private static func loadDataRepresentation(
        from provider: NSItemProvider,
        typeIdentifier: String
    ) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: typeIdentifier) { data, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let data {
                    continuation.resume(returning: data)
                } else {
                    continuation.resume(
                        throwing: NSError(domain: "ImagePickerItemProviderTests", code: -1)
                    )
                }
            }
        }
    }

    private static func itemProvider(data: Data, type: UTType) -> NSItemProvider {
        let provider = NSItemProvider()
        provider.registerDataRepresentation(
            forTypeIdentifier: type.identifier,
            visibility: .all
        ) { completion in
            completion(data, nil)
            return nil
        }
        return provider
    }

    private static func imageData(width: Int, height: Int, type: UTType) throws -> Data {
        let size = CGSize(width: width, height: height)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.systemIndigo.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            UIColor.systemYellow.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width / 3, height: height / 3))
        }

        if type == .jpeg {
            return try XCTUnwrap(image.jpegData(compressionQuality: 0.9))
        }

        let cgImage = try XCTUnwrap(image.cgImage)
        let output = NSMutableData()
        let destination = try XCTUnwrap(
            CGImageDestinationCreateWithData(output, type.identifier as CFString, 1, nil),
            "HEIC encoding unavailable on this host"
        )
        CGImageDestinationAddImage(destination, cgImage, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return output as Data
    }
}
