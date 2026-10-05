import UIKit
import UniformTypeIdentifiers
import XCTest
@testable import TTB

final class DownsampledImageDecoderTests: XCTestCase {

    func testDecodesWithinRequestedPixelCap() throws {
        let data = try Self.jpegData(width: 3024, height: 4032)

        let image = try XCTUnwrap(DownsampledImageDecoder.image(from: data, maxPixelSize: 512))

        let pixelWidth = image.size.width * image.scale
        let pixelHeight = image.size.height * image.scale
        XCTAssertLessThanOrEqual(max(pixelWidth, pixelHeight), 512)
        XCTAssertGreaterThan(min(pixelWidth, pixelHeight), 0)
    }

    func testPreservesAspectRatio() throws {
        let data = try Self.jpegData(width: 2000, height: 1000)

        let image = try XCTUnwrap(DownsampledImageDecoder.image(from: data, maxPixelSize: 400))

        let ratio = (image.size.width * image.scale) / (image.size.height * image.scale)
        XCTAssertEqual(ratio, 2.0, accuracy: 0.05)
    }

    func testDoesNotUpscaleSmallerImages() throws {
        let data = try Self.jpegData(width: 120, height: 120)

        let image = try XCTUnwrap(DownsampledImageDecoder.image(from: data, maxPixelSize: 1024))

        XCTAssertEqual(image.size.width * image.scale, 120, accuracy: 1)
        XCTAssertEqual(image.size.height * image.scale, 120, accuracy: 1)
    }

    func testReturnsNilForNonImageData() {
        let data = Data("not an image".utf8)

        XCTAssertNil(DownsampledImageDecoder.image(from: data))
    }

    func testReturnsNilForNonPositivePixelCap() throws {
        let data = try Self.jpegData(width: 100, height: 100)

        XCTAssertNil(DownsampledImageDecoder.image(from: data, maxPixelSize: 0))
    }

    func testDecodedByteCostMatchesBitmapSize() throws {
        let data = try Self.jpegData(width: 400, height: 200)
        let image = try XCTUnwrap(DownsampledImageDecoder.image(from: data, maxPixelSize: 400))

        let cost = DownsampledImageDecoder.decodedByteCost(of: image)

        // A 400x200 bitmap at 4 bytes per pixel is 320,000 bytes; allow for row padding.
        XCTAssertGreaterThanOrEqual(cost, 400 * 200 * 4)
        XCTAssertLessThan(cost, 400 * 200 * 4 * 2)
    }

    func testPicksConcreteImageTypeIdentifier() {
        let identifiers = ["public.file-url", UTType.heic.identifier, UTType.jpeg.identifier]

        XCTAssertEqual(
            DownsampledImageDecoder.imageTypeIdentifier(in: identifiers),
            UTType.heic.identifier
        )
    }

    func testReturnsNilTypeIdentifierWhenNoImageTypeRegistered() {
        XCTAssertNil(
            DownsampledImageDecoder.imageTypeIdentifier(in: ["public.plain-text", "public.file-url"])
        )
    }

    // MARK: - Fixtures

    private static func jpegData(width: Int, height: Int) throws -> Data {
        let size = CGSize(width: width, height: height)
        let renderer = UIGraphicsImageRenderer(
            size: size,
            format: {
                let format = UIGraphicsImageRendererFormat.default()
                format.scale = 1
                return format
            }()
        )
        let image = renderer.image { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            UIColor.systemPink.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width / 2, height: height / 2))
        }
        return try XCTUnwrap(image.jpegData(compressionQuality: 0.9))
    }
}
