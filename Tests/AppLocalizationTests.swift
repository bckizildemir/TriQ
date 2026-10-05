import XCTest
@testable import TTB

final class AppLocalizationTests: XCTestCase {
    func testEnglishRegionalLanguageCodesPreferEnglish() {
        XCTAssertTrue(AppLocalization.prefersEnglish(for: "en"))
        XCTAssertTrue(AppLocalization.prefersEnglish(for: "en-US"))
        XCTAssertTrue(AppLocalization.prefersEnglish(for: "en_GB"))
        XCTAssertTrue(AppLocalization.prefersEnglish(for: "EN-us"))
        XCTAssertFalse(AppLocalization.prefersEnglish(for: "tr-TR"))
    }
}
