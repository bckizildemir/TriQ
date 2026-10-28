import XCTest

// nonisolated keeps the inherited XCTestCase initializers nonisolated; the tests run in the @MainActor extension below.
nonisolated final class TopChromeColorUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = true
    }
}

@MainActor
extension TopChromeColorUITests {
    /// The status bar, navigation bar and chip row show the page color, at rest and after a scroll.
    func testHomeTopChromeHasNoGreyBand() {
        let app = launch(harness: "-ui-test-home-harness", "-ui-test-home-long-feed")
        let chip = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "home-category-chip-")).firstMatch
        XCTAssertTrue(chip.waitForExistence(timeout: 10))
        let card = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "question-card-home.")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        RunLoop.current.run(until: Date().addingTimeInterval(1))

        assertTopChromeIsPageColor(
            screen: "home",
            in: app,
            bandBottom: chip.frame.maxY + 6,
            // Pin the card by its identifier so the scrolled check reads the same card.
            scrollProbe: app.buttons[card.identifier]
        )
    }

    /// The status bar and navigation bar show the page color on Best Of, at rest and after the
    /// filter has scrolled away under the bar.
    func testBestOfTopChromeHasNoGreyBand() {
        let app = launch(harness: "-ui-test-most-answered-harness")
        let card = app.buttons["question-card-mostAnswered-preview-most-answered-1"]
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        RunLoop.current.run(until: Date().addingTimeInterval(1))

        assertTopChromeIsPageColor(
            screen: "best-of",
            in: app,
            bandBottom: app.navigationBars.firstMatch.frame.maxY + 6,
            scrollProbe: card
        )
    }

    /// The status bar and navigation bar show the page color on Trio, at rest and after the
    /// feed has scrolled under the bar (#92).
    func testTrioTopChromeHasNoGreyBand() {
        let app = launch(harness: "-ui-test-ai-harness", "-ui-test-ai-long-feed")
        let card = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "question-card-trio.feed-")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        RunLoop.current.run(until: Date().addingTimeInterval(1))

        assertTopChromeIsPageColor(
            screen: "trio",
            in: app,
            bandBottom: app.navigationBars.firstMatch.frame.maxY + 6,
            // Pin the card by its identifier so the scrolled check reads the same card.
            scrollProbe: app.buttons[card.identifier]
        )
    }

    private func launch(harness arguments: String...) -> XCUIApplication {
        // The scan expects the light page color (white); the dark variant would fail at rest.
        // `XCUIDevice` is main-actor isolated, so the switch and its restore stay in this
        // extension rather than in the nonisolated setUp and tearDown.
        let previousAppearance = XCUIDevice.shared.appearance
        XCUIDevice.shared.appearance = .light
        addTeardownBlock { @MainActor in
            // `.unspecified` cannot be set back, so only a real earlier choice is restored.
            if previousAppearance != .unspecified {
                XCUIDevice.shared.appearance = previousAppearance
            }
        }

        let app = XCUIApplication()
        app.launchArguments += arguments + ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        return app
    }

    /// Checks the band above `bandBottom` at rest, scrolls the content up, checks that
    /// `scrollProbe` moved, then checks the band again.
    private func assertTopChromeIsPageColor(
        screen: String,
        in app: XCUIApplication,
        bandBottom: CGFloat,
        scrollProbe: XCUIElement
    ) {
        let probeTop = scrollProbe.frame.minY
        assertColumnIsPageColor(state: "\(screen)-rest", bandBottom: bandBottom)

        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
        start.press(forDuration: 0.05, thenDragTo: end)
        RunLoop.current.run(until: Date().addingTimeInterval(1.5))
        // The fixture is taller than the screen, so the drag must move the content.
        XCTAssertTrue(
            !scrollProbe.exists || scrollProbe.frame.minY < probeTop - 50,
            "\(screen): the content did not scroll; the scrolled check would test the rest state again"
        )

        // From iOS 26 the system blurs the content that scrolls under the bar (the scroll-edge
        // effect), so a pixel column there is never the pure page color. The grey band this test
        // guards against only exists before iOS 26.
        if #unavailable(iOS 26.0) {
            assertColumnIsPageColor(state: "\(screen)-scrolled", bandBottom: bandBottom)
        }
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
