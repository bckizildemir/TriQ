import XCTest
@testable import TTB

final class AICategoryTests: XCTestCase {

    func testCategorizeRecognizesTurkishKeywords() {
        XCTAssertEqual(
            AICategory.categorize(question: "Sağlıklı yaşam tavsiyeleri verir misin?"),
            .health
        )
    }

    func testCategorizeRecognizesEnglishKeywords() {
        XCTAssertEqual(
            AICategory.categorize(question: "I want to travel to Tokyo. Which places should I see?"),
            .travel
        )
    }

    func testCategorizeDoesNotMatchKeywordsInsideUnrelatedWords() {
        let unrelatedQuestions = [
            "Sometimes punctuation surprises me.",
            "Multiple unrelated details appeared.",
            "A party happened at noon.",
        ]

        for question in unrelatedQuestions {
            XCTAssertEqual(
                AICategory.categorize(question: question),
                .other,
                "Unexpected category for \(question)"
            )
        }
    }

    func testCategorizeTreatsBlankAndPunctuationOnlyInputAsOther() {
        XCTAssertEqual(AICategory.categorize(question: " \n\t "), .other)
        XCTAssertEqual(AICategory.categorize(question: "...?!"), .other)
    }
}
