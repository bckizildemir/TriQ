import XCTest
@testable import TTB

final class AnswerImageSuggestionTests: XCTestCase {
    func testFunctionsValue_acceptsValidRequiredFieldsAndFallsBackToPhotoId() throws {
        let suggestion = try XCTUnwrap(
            AnswerImageSuggestion(
                functionsValue: makeFunctionsValue()
            )
        )

        XCTAssertEqual(suggestion.id, "photo-1")
        XCTAssertEqual(suggestion.photoId, "photo-1")
        XCTAssertEqual(suggestion.thumbnailURL, "https://example.com/thumbnail.jpg")
        XCTAssertEqual(suggestion.previewURL, "https://example.com/preview.jpg")
        XCTAssertEqual(suggestion.fullSizeURL, "https://example.com/full.jpg")
    }

    func testFunctionsValue_rejectsBlankRequiredIdentifiersAndURLs() {
        for key in ["id", "photoId", "thumbnailURL", "previewURL", "fullSizeURL"] {
            var value = makeFunctionsValue()
            value[key] = " \n\t "

            XCTAssertNil(
                AnswerImageSuggestion(functionsValue: value),
                "Expected whitespace-only \(key) to be rejected"
            )
        }
    }

    func testFunctionsValue_preservesValidExplicitID() throws {
        var value = makeFunctionsValue()
        value["id"] = "suggestion-1"

        let suggestion = try XCTUnwrap(AnswerImageSuggestion(functionsValue: value))

        XCTAssertEqual(suggestion.id, "suggestion-1")
    }

    func testFunctionsValue_rejectsWrongTypeIDAndMalformedRemoteURLs() {
        var wrongTypeID = makeFunctionsValue()
        wrongTypeID["id"] = 7
        XCTAssertNil(AnswerImageSuggestion(functionsValue: wrongTypeID))

        for key in ["thumbnailURL", "previewURL", "fullSizeURL"] {
            var value = makeFunctionsValue()
            value[key] = "not a remote URL"

            XCTAssertNil(
                AnswerImageSuggestion(functionsValue: value),
                "Expected malformed \(key) to be rejected"
            )
        }
    }

    private func makeFunctionsValue() -> [String: Any] {
        [
            "photoId": "photo-1",
            "thumbnailURL": "https://example.com/thumbnail.jpg",
            "previewURL": "https://example.com/preview.jpg",
            "fullSizeURL": "https://example.com/full.jpg",
        ]
    }
}
