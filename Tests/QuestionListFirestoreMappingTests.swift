import FirebaseFirestore
import Foundation
import Testing
@testable import TTB

/// `fromFirestore` for the list, share-recipient and AI query models. A listener closure forwards
/// raw document data to these, so the defaults and the drop rules are tested here without Firebase.
struct QuestionListFirestoreMappingTests {
    private let created = Date(timeIntervalSince1970: 1_700_000_000)
    private let updated = Date(timeIntervalSince1970: 1_700_005_000)

    // MARK: QuestionList

    @Test func questionListMapsEveryField() throws {
        let list = try #require(QuestionList.fromFirestore(
            [
                "ownerId": "owner",
                "name": "Favorites",
                "questionIds": ["q1", "q2"],
                "visibility": "shared",
                "createdAt": Timestamp(date: created),
                "updatedAt": Timestamp(date: updated),
            ],
            id: "l1"
        ))

        #expect(list.id == "l1")
        #expect(list.ownerId == "owner")
        #expect(list.name == "Favorites")
        #expect(list.questionIds == ["q1", "q2"])
        #expect(list.visibility == "shared")
        #expect(list.createdAt == created)
        #expect(list.updatedAt == updated)
    }

    @Test func questionListWithoutARequiredFieldIsDropped() {
        #expect(QuestionList.fromFirestore(["name": "No owner"], id: "l1") == nil)
        #expect(QuestionList.fromFirestore(["ownerId": "owner"], id: "l1") == nil)
        #expect(QuestionList.fromFirestore(["ownerId": 7, "name": "Owner is not a string"], id: "l1") == nil)
    }

    @Test func questionListFallsBackToDefaults() throws {
        let list = try #require(QuestionList.fromFirestore(
            ["ownerId": "owner", "name": "Bare", "createdAt": Timestamp(date: created)],
            id: "l1"
        ))

        #expect(list.questionIds.isEmpty)
        #expect(list.visibility == "private")
        #expect(list.updatedAt == created)
    }

    @Test func questionListIgnoresAWrongTypedQuestionIds() throws {
        let list = try #require(QuestionList.fromFirestore(
            ["ownerId": "owner", "name": "Bad ids", "questionIds": [1, 2]],
            id: "l1"
        ))

        #expect(list.questionIds.isEmpty)
    }

    // MARK: QuestionListShareRecipient

    @Test func recipientMapsEveryField() throws {
        let recipient = try #require(QuestionListShareRecipient.fromFirestore(
            [
                "recipientId": "r1",
                "recipientDisplayName": "Ada",
                "status": "accepted",
                "latestReplyAnswerSnapshots": ["q1": [" a ", "b"], "q2": "not an array"],
                "repliedAt": Timestamp(date: updated),
                "unreadByOwner": true,
                "acceptedAt": Timestamp(date: created),
                "updatedAt": Timestamp(date: updated),
            ],
            id: "doc",
            shareId: "s1"
        ))

        #expect(recipient.id == "r1")
        #expect(recipient.shareId == "s1")
        #expect(recipient.recipientDisplayName == "Ada")
        #expect(recipient.status == .accepted)
        #expect(recipient.latestReplyAnswerSnapshots == ["q1": ["a", "b", ""]])
        #expect(recipient.repliedAt == updated)
        #expect(recipient.unreadByOwner)
        #expect(recipient.acceptedAt == created)
        #expect(recipient.updatedAt == updated)
    }

    @Test func recipientFallsBackToTheDocumentIdAndDefaults() throws {
        let recipient = try #require(QuestionListShareRecipient.fromFirestore(
            ["acceptedAt": Timestamp(date: created)],
            id: "doc",
            shareId: "s1"
        ))

        #expect(recipient.recipientId == "doc")
        #expect(recipient.recipientDisplayName == "TTB user")
        #expect(recipient.status == .unknown)
        #expect(recipient.latestReplyAnswerSnapshots.isEmpty)
        #expect(recipient.repliedAt == nil)
        #expect(!recipient.unreadByOwner)
        #expect(recipient.updatedAt == created)
    }

    @Test func recipientUpdatedAtPrefersRepliedAtOverAcceptedAt() throws {
        let recipient = try #require(QuestionListShareRecipient.fromFirestore(
            ["repliedAt": Timestamp(date: updated), "acceptedAt": Timestamp(date: created)],
            id: "doc",
            shareId: "s1"
        ))

        #expect(recipient.updatedAt == updated)
    }

    @Test func recipientWithAnEmptyIdAndNoRecipientIdIsDropped() {
        #expect(QuestionListShareRecipient.fromFirestore([:], id: "", shareId: "s1") == nil)
        #expect(QuestionListShareRecipient.fromFirestore(["recipientId": ""], id: "doc", shareId: "s1") == nil)
    }

    @Test func recipientWithAnUnknownStatusStringIsUnknown() throws {
        let recipient = try #require(QuestionListShareRecipient.fromFirestore(
            ["status": "banished"],
            id: "doc",
            shareId: "s1"
        ))

        #expect(recipient.status == .unknown)
    }

    // MARK: AIQuery

    private func validQueryData() -> [String: Any] {
        [
            "question": "Best books?",
            "responses": ["One", "Two", "Three"],
            "timestamp": Timestamp(date: created),
            "category": AICategory.other.rawValue,
            "isSaved": true,
            "isLoading": false,
        ]
    }

    @Test func aiQueryMapsEveryField() throws {
        var data = validQueryData()
        data["error"] = "boom"
        let query = try #require(AIQuery.fromFirestore(data, id: "a1"))

        #expect(query.id == "a1")
        #expect(query.question == "Best books?")
        #expect(query.responses == ["One", "Two", "Three"])
        #expect(query.timestamp == created)
        #expect(query.category == .other)
        #expect(query.isSaved)
        #expect(!query.isLoading)
        #expect(query.error == "boom")
    }

    @Test func aiQueryWithoutAnErrorFieldHasNoError() throws {
        let query = try #require(AIQuery.fromFirestore(validQueryData(), id: "a1"))

        #expect(query.error == nil)
    }

    @Test func aiQueryWithANonStringErrorHasNoError() throws {
        var data = validQueryData()
        data["error"] = NSNull()
        let query = try #require(AIQuery.fromFirestore(data, id: "a1"))

        #expect(query.error == nil)
    }

    @Test(arguments: ["question", "responses", "timestamp", "category", "isSaved", "isLoading"])
    func aiQueryWithoutARequiredFieldIsDropped(missing: String) {
        var data = validQueryData()
        data[missing] = nil

        #expect(AIQuery.fromFirestore(data, id: "a1") == nil)
    }

    @Test func aiQueryWithAnUnknownCategoryIsDropped() {
        var data = validQueryData()
        data["category"] = "not-a-category"

        #expect(AIQuery.fromFirestore(data, id: "a1") == nil)
    }

    @Test func aiQueryKeepsAnyNumberOfResponses() throws {
        var data = validQueryData()
        data["responses"] = [String]()
        let query = try #require(AIQuery.fromFirestore(data, id: "a1"))

        #expect(query.responses.isEmpty)
        #expect(!query.isComplete)
    }
}
