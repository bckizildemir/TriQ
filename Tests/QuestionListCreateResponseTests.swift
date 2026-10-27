import Foundation
import Testing
@testable import TTB

/// The response guard `QuestionListService.createList` runs on the `createQuestionList` callable's
/// payload. Tested without Firebase.
struct QuestionListCreateResponseTests {
    @Test func aListIdIsRead() throws {
        #expect(try QuestionListService.listId(from: ["listId": "l1"]) == "l1")
    }

    @Test func aPayloadWithoutAUsableListIdIsInvalid() {
        let payloads: [Any] = [
            [String: Any](),
            ["listId": ""],
            ["listId": 7],
            "l1",
            NSNull(),
        ]

        for payload in payloads {
            #expect(throws: QuestionListService.QuestionListError.invalidResponse) {
                try QuestionListService.listId(from: payload)
            }
        }
    }
}
