import FirebaseFirestore
import Testing
@testable import TTB

struct UserDocumentWritePlanTests {
    /// The keys `firestore.rules` lets a regular user change on their own `users/{userId}` document
    /// (`allow update`). A patch that names any other key is refused as a whole, `updatedAt`
    /// included, so the write plan may only ever use these.
    private static let updateRuleAllowedKeys: Set<String> = [
        "username", "email", "updatedAt", "hasProfilePicture",
        "usernameNormalized", "profileImageURL", "isAnonymous",
        "onboardingVersion", "onboardingCompletedAt",
        "termsAcceptedVersion", "privacyAcceptedVersion", "legalAcceptedAt",
    ]

    @Test func absentDocumentIsCreated() {
        let plan = LiveAuthUserDocumentManager.writePlan(existing: nil, isAnonymous: true)
        guard case .create = plan else {
            Issue.record("Expected .create, got \(plan)")
            return
        }
    }

    @Test func emptyDocumentGetsOnlyTheFieldsTheUpdateRuleAllows() throws {
        let patch = try #require(
            LiveAuthUserDocumentManager.writePlan(existing: [:], isAnonymous: true).patch)

        #expect(patch["isAnonymous"] as? Bool == true)
        #expect(patch["updatedAt"] != nil)
        #expect(patch["createdAt"] == nil)
        #expect(patch["usernameNormalized"] == nil)
        #expect(Set(patch.keys) == ["isAnonymous", "updatedAt"])
    }

    @Test func completeDocumentOnlyGetsUpdatedAt() throws {
        let complete: [String: Any] = [
            "dailyAnswers": 1, "weeklyAnswers": 1, "totalAnswered": 1,
            "completedQuestionIds": ["q"], "categoryAnswers": ["c": 1],
            "currentStreak": 1, "unlockedBadges": ["b"], "badgeProgress": ["b": 0.5],
            "isAnonymous": false, "usernameNormalized": "tester", "username": "Tester",
        ]
        let patch = try #require(
            LiveAuthUserDocumentManager.writePlan(existing: complete, isAnonymous: true).patch)

        #expect(Set(patch.keys) == ["updatedAt"])
    }

    @Test func missingNormalizedUsernameIsDerivedFromUsername() throws {
        let patch = try #require(
            LiveAuthUserDocumentManager.writePlan(
                existing: ["username": "Tester"], isAnonymous: false
            ).patch)

        #expect(patch["usernameNormalized"] as? String == AuthModel.normalizedUsername("Tester"))
        #expect(patch["isAnonymous"] as? Bool == false)
    }

    /// #116: an old document without the stats fields used to get them backfilled by the client,
    /// and the rules refused that patch. The patch now leaves them to `saveAnswer`, which merges
    /// them on the user's next answer, and stays inside the update allowlist.
    @Test func oldDocumentWithoutStatsIsPatchedOnlyInsideTheUpdateAllowlist() throws {
        let oldDocument: [String: Any] = [
            "username": "Tester",
            "email": "tester@example.com",
            "isAnonymous": false,
        ]
        let patch = try #require(
            LiveAuthUserDocumentManager.writePlan(existing: oldDocument, isAnonymous: true).patch)

        #expect(Set(patch.keys).isSubset(of: Self.updateRuleAllowedKeys))
        // The one field worth backfilling from the client still is, and no stat comes along.
        #expect(Set(patch.keys) == ["updatedAt", "usernameNormalized"])
    }

    @Test func everyPatchStaysInsideTheUpdateAllowlist() throws {
        let documents: [[String: Any]] = [
            [:],
            ["username": "Tester"],
            ["usernameNormalized": "tester", "isAnonymous": true],
            ["dailyAnswers": 3, "totalAnswered": 9, "unlockedBadges": ["b"]],
        ]

        for document in documents {
            let patch = try #require(
                LiveAuthUserDocumentManager.writePlan(existing: document, isAnonymous: false).patch)
            let description = "\(document.keys.sorted()) produced \(patch.keys.sorted())"
            #expect(Set(patch.keys).isSubset(of: Self.updateRuleAllowedKeys), "\(description)")
        }
    }
}

private extension LiveAuthUserDocumentManager.UserDocumentWrite {
    /// The patch of a `.patch` plan, or `nil` for `.create`.
    var patch: [String: Any]? {
        guard case .patch(let patch) = self else { return nil }
        return patch
    }
}
