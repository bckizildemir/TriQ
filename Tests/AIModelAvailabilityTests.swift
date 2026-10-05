import Combine
import Testing
@testable import TTB

@MainActor
struct AIModelAvailabilityTests {
    /// Builds the model for a non-guest user, so the daily limit never depends on the
    /// simulator's persisted Firebase user. A leftover anonymous user would apply the
    /// guest daily limit and break every quota expectation below.
    private func makeModel(
        aiService: MockAIService,
        usageService: MockAIUsageService
    ) -> AIModel {
        AIModel(
            aiService: aiService,
            usageService: usageService,
            isAnonymousUser: { false }
        )
    }

    @Test
    func serviceAvailabilityDependsOnUsageLimitsNotBundledProviderKeys() async {
        let model = makeModel(aiService: MockAIService(), usageService: MockAIUsageService())
        await model.refreshUsageStats()

        #expect(model.isServiceAvailable)
        #expect(model.serviceStatusMessage == nil)
    }

    @Test
    func successfulResponseSurvivesUsagePersistenceFailure() async throws {
        let usageService = MockAIUsageService()
        await usageService.setUpdateUsageError(.updateFailed)
        let model = makeModel(aiService: MockAIService(), usageService: usageService)
        await model.refreshUsageStats()

        await model.askQuestion("What should I remember?", category: .other)

        let query = try #require(model.recentQueries.first)
        #expect(query.responses.count == 3)
        #expect(query.error == nil)
        #expect(model.error?.isEmpty == false)
        #expect(model.isLoading == false)
    }

    @Test
    func loadingRemainsVisibleUntilAllConcurrentRequestsFinish() async {
        let aiService = MockAIService()
        await aiService.blockQuestion("First request")
        await aiService.blockQuestion("Second request")
        let model = makeModel(aiService: aiService, usageService: MockAIUsageService())
        await model.refreshUsageStats()

        let firstRequest = Task {
            await model.askQuestion("First request", category: .other)
        }
        await aiService.waitUntilQuestionStarts("First request")

        let secondRequest = Task {
            await model.askQuestion("Second request", category: .other)
        }
        await aiService.waitUntilQuestionStarts("Second request")

        await aiService.resumeQuestion("First request")
        await firstRequest.value

        #expect(model.isLoading)

        await aiService.resumeQuestion("Second request")
        await secondRequest.value

        #expect(model.isLoading == false)
    }

    @Test(.timeLimit(.minutes(1)))
    func concurrentRequestsPersistUsageSnapshotsInOrder() async {
        let usageService = MockAIUsageService()
        await usageService.blockUpdate(dailyQueries: 1)
        let model = makeModel(aiService: MockAIService(), usageService: usageService)
        await model.refreshUsageStats()

        let firstRequest = Task {
            await model.askQuestion("First request", category: .other)
        }
        await usageService.waitUntilUpdateStarts(dailyQueries: 1)

        let (usageUpdates, usageContinuation) = AsyncStream.makeStream(
            of: Int.self,
            bufferingPolicy: .bufferingNewest(1)
        )
        let usageObservation = model.$usageStats.sink { stats in
            usageContinuation.yield(stats.dailyQueries)
        }
        defer {
            usageObservation.cancel()
            usageContinuation.finish()
        }

        let secondRequest = Task {
            await model.askQuestion("Second request", category: .other)
        }
        for await dailyQueries in usageUpdates {
            if dailyQueries == 2 {
                break
            }
        }

        #expect(await usageService.hasUpdateStarted(dailyQueries: 2) == false)

        await usageService.resumeUpdate(dailyQueries: 1)
        await firstRequest.value
        await secondRequest.value

        #expect(await usageService.getPersistedDailyQueryCounts() == [1, 2])
    }

    @Test
    func concurrentRequestsCannotOversubscribeLastQuotaSlot() async {
        let aiService = MockAIService()
        await aiService.blockQuestion("Admitted request")
        let usageService = MockAIUsageService()
        await usageService.setMockUsageStats(
            AIUsageStats(
                dailyQueries: 19,
                weeklyQueries: 19,
                monthlyQueries: 19
            )
        )
        let model = makeModel(aiService: aiService, usageService: usageService)
        await model.refreshUsageStats()

        let admittedRequest = Task {
            await model.askQuestion("Admitted request", category: .other)
        }
        await aiService.waitUntilQuestionStarts("Admitted request")

        #expect(model.canMakeQuery == false)
        await model.askQuestion("Rejected request", category: .other)
        #expect(await aiService.hasQuestionStarted("Rejected request") == false)

        await aiService.resumeQuestion("Admitted request")
        await admittedRequest.value

        #expect(model.usageStats.dailyQueries == 20)
        #expect(model.recentQueries.map(\.question) == ["Admitted request"])
    }

    @Test
    func failedRequestReleasesReservedQuotaSlot() async {
        let aiService = MockAIService()
        await aiService.setShouldFail(true)
        let usageService = MockAIUsageService()
        await usageService.setMockUsageStats(
            AIUsageStats(
                dailyQueries: 19,
                weeklyQueries: 19,
                monthlyQueries: 19
            )
        )
        let model = makeModel(aiService: aiService, usageService: usageService)
        await model.refreshUsageStats()

        await model.askQuestion("Failed request", category: .other)

        #expect(model.canMakeQuery)
        #expect(model.usageStats.dailyQueries == 19)
    }

    @Test
    func olderFailureDoesNotOverwriteLatestRequestErrorState() async {
        let aiService = MockAIService()
        await aiService.blockQuestion("Older request")
        let model = makeModel(aiService: aiService, usageService: MockAIUsageService())
        await model.refreshUsageStats()

        let olderRequest = Task {
            await model.askQuestion("Older request", category: .other)
        }
        await aiService.waitUntilQuestionStarts("Older request")

        await model.askQuestion("Latest request", category: .other)
        await aiService.setShouldFail(true)
        await aiService.resumeQuestion("Older request")
        await olderRequest.value

        #expect(model.error == nil)
        #expect(model.recentQueries.first(where: { $0.question == "Older request" })?.error != nil)
        #expect(model.recentQueries.first(where: { $0.question == "Latest request" })?.isComplete == true)
    }

    @Test
    func completedRequestDoesNotEraseWhitespaceEditedDraft() async {
        let aiService = MockAIService()
        await aiService.blockQuestion("Submitted question")
        let model = makeModel(aiService: aiService, usageService: MockAIUsageService())
        await model.refreshUsageStats()
        model.currentQuery = "Submitted question"

        let request = Task {
            await model.askQuestion("Submitted question", category: .other)
        }
        await aiService.waitUntilQuestionStarts("Submitted question")
        model.currentQuery = "Submitted question "

        await aiService.resumeQuestion("Submitted question")
        await request.value

        #expect(model.currentQuery == "Submitted question ")
    }

    @Test(.timeLimit(.minutes(1)))
    func initialUsageLoadFailsClosedUntilQuotaIsKnown() async {
        let aiService = MockAIService()
        let usageService = MockAIUsageService()
        await usageService.setMockUsageStats(
            AIUsageStats(
                dailyQueries: 20,
                weeklyQueries: 20,
                monthlyQueries: 20
            )
        )
        await usageService.blockGetUsageStats()

        let model = makeModel(aiService: aiService, usageService: usageService)
        await usageService.waitUntilGetUsageStatsStarts(callCount: 1)

        #expect(model.canMakeQuery == false)
        await model.askQuestion("Must not be admitted", category: .other)
        #expect(await aiService.hasQuestionStarted("Must not be admitted") == false)

        let refresh = Task {
            await model.refreshUsageStats()
        }
        await usageService.resumeGetUsageStats()
        await refresh.value

        #expect(model.usageStats.dailyQueries == 20)
        #expect(model.canMakeQuery == false)
    }

    @Test(.timeLimit(.minutes(1)))
    func staleUsageRefreshCannotOverwriteLocalIncrement() async {
        let usageService = MockAIUsageService()
        let model = makeModel(aiService: MockAIService(), usageService: usageService)
        await model.refreshUsageStats()

        await usageService.blockGetUsageStats()
        let refreshCallCount = await usageService.getUsageStatsCallCount() + 1
        let refresh = Task {
            await model.refreshUsageStats()
        }
        await usageService.waitUntilGetUsageStatsStarts(
            callCount: refreshCallCount
        )

        await model.askQuestion("Count this request", category: .other)
        #expect(model.usageStats.dailyQueries == 1)

        await usageService.resumeGetUsageStats()
        await refresh.value

        #expect(model.usageStats.dailyQueries == 1)
        #expect(await usageService.getPersistedDailyQueryCounts() == [1])
    }

    @Test(.timeLimit(.minutes(1)))
    func staleUsageRefreshCannotOverwriteInFlightReservation() async {
        let aiService = MockAIService()
        await aiService.blockQuestion("Use the final slot")
        let usageService = MockAIUsageService()
        await usageService.setMockUsageStats(
            AIUsageStats(
                dailyQueries: 19,
                weeklyQueries: 19,
                monthlyQueries: 19
            )
        )
        let model = makeModel(aiService: aiService, usageService: usageService)
        await model.refreshUsageStats()

        await usageService.setMockUsageStats(AIUsageStats())
        await usageService.blockGetUsageStats()
        let refreshCallCount = await usageService.getUsageStatsCallCount() + 1
        let refresh = Task {
            await model.refreshUsageStats()
        }
        await usageService.waitUntilGetUsageStatsStarts(
            callCount: refreshCallCount
        )

        let request = Task {
            await model.askQuestion("Use the final slot", category: .other)
        }
        await aiService.waitUntilQuestionStarts("Use the final slot")

        await usageService.resumeGetUsageStats()
        await refresh.value

        #expect(model.usageStats.dailyQueries == 19)
        #expect(model.canMakeQuery == false)

        await aiService.resumeQuestion("Use the final slot")
        await request.value

        #expect(model.usageStats.dailyQueries == 20)
        #expect(await usageService.getPersistedDailyQueryCounts() == [20])
    }

    @Test(arguments: [
        (isAnonymous: true, dailyQueries: 4, canMakeQuery: true),
        (isAnonymous: true, dailyQueries: 5, canMakeQuery: false),
        (isAnonymous: false, dailyQueries: 19, canMakeQuery: true),
        (isAnonymous: false, dailyQueries: 20, canMakeQuery: false)
    ])
    func dailyLimitFollowsInjectedGuestState(
        isAnonymous: Bool,
        dailyQueries: Int,
        canMakeQuery: Bool
    ) async {
        let usageService = MockAIUsageService()
        await usageService.setMockUsageStats(
            AIUsageStats(dailyQueries: dailyQueries)
        )
        let model = AIModel(
            aiService: MockAIService(),
            usageService: usageService,
            isAnonymousUser: { isAnonymous }
        )
        await model.refreshUsageStats()

        #expect(model.canMakeQuery == canMakeQuery)
    }
}
