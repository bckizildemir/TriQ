import XCTest
@testable import TTB

/// What keeps the UI-test harness out of a release binary.
///
/// `TTB/` is a file-system-synchronized root group with six membership exceptions and no
/// per-configuration membership, and there are only three targets — a separate harness framework
/// could not see the app's `internal` types. So `#if DEBUG` is the only available gate, and until
/// this file nothing checked it: FIX-1 shipped a test double in a release build exactly that way,
/// and adding a fifteenth harness file still defaulted to shipped.
///
/// Three rules, all structural. Every harness file lives in one directory, every file in that
/// directory is gated, and only two named production files read the launch options at all.
/// `AppCheckPolicyTests` is the precedent for pinning a Release guarantee from a Debug run;
/// `functions/aiCallableWiring.test.js` is the precedent for failing when a file bypasses its
/// wrapper.
final class HarnessLayerIsolationTests: XCTestCase {

    /// `UITestLaunchOptions` is production code and stays out of the harness directory: `TTBApp`
    /// dispatches on it and `AppCheckPolicy` consults it, so gating it would break the release build.
    private let productionLaunchOptions = "UITestLaunchOptions.swift"

    func testEveryHarnessFileLivesInTheHarnessDirectory() throws {
        let strays = try appSourceFiles()
            .filter { $0.lastPathComponent.hasPrefix("UITest") }
            .filter { $0.lastPathComponent != productionLaunchOptions }
            .filter { $0.deletingLastPathComponent().lastPathComponent != "UITestSupport" }
            .map(\.lastPathComponent)

        XCTAssertEqual(
            strays,
            [],
            "Harness files belong in TTB/UITestSupport/, where one test can check all of them"
        )
    }

    /// AD-3's own purpose, pinned: production code must not ask whether it runs inside a UI test.
    ///
    /// Two files read the launch options, and each is structural rather than left over. `TTBApp`
    /// dispatches to a harness root. `AppCheckPolicy` runs in `AppDelegate` before any `View`
    /// exists, so a view modifier is the wrong lifecycle stage for it — `docs/adr/0008` records
    /// both. `HomeView` used to be a third, guarding one of `BadgeModel`'s four construction sites;
    /// FIX-6 moved that decision onto `AppEnvironment`, so `HomeView` no longer asks.
    /// `UITestLaunchOptions` is excluded because it *defines* the flag rather than reading it, so a
    /// third reader here fails the suite.
    func testOnlyKnownProductionFilesReadTheLaunchOptions() throws {
        let knownReaders = ["AppCheckPolicy.swift", "TTBApp.swift"]

        let readers = try appSourceFiles()
            .filter { $0.deletingLastPathComponent().lastPathComponent != "UITestSupport" }
            .filter { $0.lastPathComponent != productionLaunchOptions }
            .filter { try readsLaunchOptions($0) }
            .map(\.lastPathComponent)
            .sorted()

        XCTAssertEqual(
            readers,
            knownReaders,
            "A new production reader of the launch options is the leak AD-3 removed and FIX-6 finished"
        )
    }

    func testEveryHarnessFileIsGatedOutOfARelease() throws {
        let files = try harnessFiles()

        // A path that stopped matching would otherwise pass by finding nothing.
        XCTAssertGreaterThan(files.count, 10, "The harness directory should not be nearly empty")

        for file in files {
            let lines = try String(contentsOf: file, encoding: .utf8)
                .components(separatedBy: .newlines)

            XCTAssertEqual(
                firstDeclarationLine(in: lines),
                "#if DEBUG",
                "\(file.lastPathComponent) should open with a top-level #if DEBUG"
            )
            XCTAssertEqual(
                lines.last(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }),
                "#endif",
                "\(file.lastPathComponent) should close its #if DEBUG at the end of the file"
            )
        }
    }

    // MARK: - Helpers

    /// Whether the file *reads* the launch options, rather than mentioning them in a comment: a
    /// doc comment that explains what AD-3 removed is not itself a leak.
    private func readsLaunchOptions(_ file: URL) throws -> Bool {
        try String(contentsOf: file, encoding: .utf8)
            .components(separatedBy: .newlines)
            .contains {
                let line = $0.trimmingCharacters(in: .whitespaces)
                return !line.hasPrefix("//") && line.contains("UITestLaunchOptions")
            }
    }

    /// The first line that declares anything: imports and comments come before the gate, code
    /// cannot.
    private func firstDeclarationLine(in lines: [String]) -> String? {
        lines
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first {
                !$0.isEmpty
                    && !$0.hasPrefix("//")
                    && !$0.hasPrefix("import ")
            }
    }

    private func harnessFiles() throws -> [URL] {
        try appSourceFiles()
            .filter { $0.deletingLastPathComponent().lastPathComponent == "UITestSupport" }
    }

    /// Every Swift file under `TTB/`, found from this file's own path so the check works from a
    /// checkout rather than from whatever the test bundle happens to contain.
    private func appSourceFiles() throws -> [URL] {
        let appSources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("TTB")

        let enumerator = try XCTUnwrap(
            FileManager.default.enumerator(at: appSources, includingPropertiesForKeys: nil),
            "TTB/ should be readable from \(appSources.path)"
        )

        return enumerator
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" }
    }
}
