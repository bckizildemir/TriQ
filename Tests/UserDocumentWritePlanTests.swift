import FirebaseFirestore
import Testing
@testable import TTB

struct UserDocumentWritePlanTests {
    @Test func absentDocumentIsCreated() {
        let plan = LiveAuthUserDocumentManager.writePlan(existing: nil, isAnonymous: true)
        guard case .create = plan else {
            Issue.record("Expected .create, got \(plan)")
            return
        }
    }

    @Test func emptyDocumentGetsEveryDefaultButNoCreatedAt() throws {
        let plan = LiveAuthUserDocumentManager.writePlan(existing: [:], isAnonymous: true)
        guard case .patch(let patch) = plan else {
            Issue.record("Expected .patch, got \(plan)")
            return
        }
        #expect(patch["isAnonymous"] as? Bool == true)
        #expect(patch["totalAnswered"] as? Int == 0)
        #expect(patch["updatedAt"] != nil)
        #expect(patch["createdAt"] == nil)
        #expect(patch["usernameNormalized"] == nil)
    }

    @Test func completeDocumentOnlyGetsUpdatedAt() {
        let complete: [String: Any] = [
            "dailyAnswers": 1, "weeklyAnswers": 1, "totalAnswered": 1,
            "completedQuestionIds": ["q"], "categoryAnswers": ["c": 1],
            "currentStreak": 1, "unlockedBadges": ["b"], "badgeProgress": ["b": 0.5],
            "isAnonymous": false, "usernameNormalized": "tester", "username": "Tester",
        ]
        let plan = LiveAuthUserDocumentManager.writePlan(existing: complete, isAnonymous: true)
        guard case .patch(let patch) = plan else {
            Issue.record("Expected .patch, got \(plan)")
            return
        }
        #expect(Set(patch.keys) == ["updatedAt"])
    }

    @Test func missingNormalizedUsernameIsDerivedFromUsername() {
        let plan = LiveAuthUserDocumentManager.writePlan(
            existing: ["username": "Tester"], isAnonymous: false)
        guard case .patch(let patch) = plan else {
            Issue.record("Expected .patch, got \(plan)")
            return
        }
        #expect(patch["usernameNormalized"] as? String == AuthModel.normalizedUsername("Tester"))
        #expect(patch["isAnonymous"] as? Bool == false)
    }
}
