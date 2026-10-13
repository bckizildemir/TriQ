import XCTest

// nonisolated keeps the inherited XCTestCase initializers nonisolated; the tests run in the @MainActor extension below.
nonisolated final class HomeTopChromeColorUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = true
    }
}

@MainActor
extension HomeTopChromeColorUITests {
    /// The status bar, navigation bar and chip row show the page color, at rest and after a scroll.
    func testTopChromeHasNoGreyBand() {
        let app = XCUIApplication()
        app.launchArguments += [
            "-ui-test-home-harness",
            "-ui-test-home-long-feed",
            "-AppleLanguages",
            "(en)",
            "-AppleLocale",
            "en_US"
        ]
        app.launch()
        let chip = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "home-category-chip-")).firstMatch
        XCTAssertTrue(chip.waitForExistence(timeout: 10))
        RunLoop.current.run(until: Date().addingTimeInterval(1))
        let bandBottom = chip.frame.maxY + 6
        let anyCard = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "question-card-home.")).firstMatch
        XCTAssertTrue(anyCard.waitForExistence(timeout: 5))
        // Pin the card by its identifier so the scrolled check reads the same card.
        let firstCard = app.buttons[anyCard.identifier]
        let firstCardTop = firstCard.frame.minY

        assertColumnIsPageColor(state: "rest", bandBottom: bandBottom)

        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
        start.press(forDuration: 0.05, thenDragTo: end)
        RunLoop.current.run(until: Date().addingTimeInterval(1.5))
        // The long-feed fixture is taller than the screen, so the drag must move the feed.
        XCTAssertTrue(
            !firstCard.exists || firstCard.frame.minY < firstCardTop - 50,
            "the feed did not scroll; the scrolled check would test the rest state again"
        )

        assertColumnIsPageColor(state: "scrolled", bandBottom: bandBottom)
    }

    /// Scans the pixel column 4 pt from the leading edge, left of every title, button and chip.
    private func assertColumnIsPageColor(state: String, bandBottom: CGFloat) {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "top-chrome-\(state)"
        attachment.lifetime = .keepAlways
        add(attachment)

        guard let image = screenshot.image.cgImage else {
            return XCTFail("no CGImage")
        }
        let scale = CGFloat(image.width) / screenshot.image.size.width
        let pixels = RGBAPixels(image)
        let x = Int(4 * scale)
        var offRows: [Int] = []
        var worst: (r: Int, g: Int, b: Int) = (255, 255, 255)
        for y in 0..<Int(bandBottom * scale) {
            let pixel = pixels[x, y]
            if min(pixel.r, pixel.g, pixel.b) < 250 {
                offRows.append(y)
                if pixel.r + pixel.g + pixel.b < worst.r + worst.g + worst.b { worst = pixel }
            }
        }
        XCTAssertTrue(
            offRows.isEmpty,
            "\(state): \(offRows.count) rows above y=\(Int(bandBottom)) pt are not the page color; first at \(offRows.first.map { CGFloat($0) / scale } ?? 0) pt, darkest \(worst)"
        )
    }
}

private struct RGBAPixels {
    private let bytes: [UInt8]
    private let width: Int

    init(_ image: CGImage) {
        width = image.width
        var buffer = [UInt8](repeating: 0, count: image.width * image.height * 4)
        buffer.withUnsafeMutableBytes { raw in
            let context = CGContext(
                data: raw.baseAddress,
                width: image.width,
                height: image.height,
                bitsPerComponent: 8,
                bytesPerRow: image.width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
            context?.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        bytes = buffer
    }

    subscript(x: Int, y: Int) -> (r: Int, g: Int, b: Int) {
        let index = (y * width + x) * 4
        return (Int(bytes[index]), Int(bytes[index + 1]), Int(bytes[index + 2]))
    }
}
