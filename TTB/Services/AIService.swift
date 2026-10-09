//
//  AIService.swift
//  TTB
//
//  Created by AI Assistant on 2025-07-18.
//

import FirebaseFunctions
import Foundation

// MARK: - AI Service Protocol
protocol AIServiceProtocol: Sendable {
    func askQuestion(_ question: String, category: AICategory) async throws -> [String]
    func suggestAnswers(for question: String) async throws -> [String]
    func suggestQuickAnswers(
        for question: String,
        category: String,
        excluding: [String],
        languageName: String?,
        limit: Int
    ) async throws -> [String]
    func generateQuestionPrompt(from idea: String, category: String) async throws -> String
    func generateQuestionVariations(from topic: String, count: Int) async throws -> [String]
    func generateTrioQuestionSuggestions(
        from topic: String,
        count: Int,
        excluding: [String],
        availableCategoryIDs: [String]
    ) async throws -> TrioQuestionSuggestionResult
}

// MARK: - AI Service Errors
enum AIServiceError: LocalizedError {
    case invalidURL
    case noAPIKey
    case invalidResponse
    case networkError(Error)
    case rateLimitExceeded
    case invalidResponseFormat
    case emptyResponse
    case apiKeyInvalid
    case timeout
    case serverError(Int)
    case parsingError
    case insufficientResponses(Int)
    case refused(CallableRefusal)
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return String(localized: "ai.error.invalidURL")
        case .noAPIKey:
            return String(localized: "ai.error.noAPIKey")
        case .invalidResponse:
            return String(localized: "ai.error.invalidResponse")
        case .networkError(let error):
            return String(
                format: String(localized: "ai.error.network"),
                locale: AppLocalization.currentLocale,
                error.localizedDescription
            )
        case .rateLimitExceeded:
            return String(localized: "ai.error.rateLimit")
        case .invalidResponseFormat:
            return String(localized: "ai.error.invalidResponseFormat")
        case .emptyResponse:
            return String(localized: "ai.error.emptyResponse")
        case .apiKeyInvalid:
            return String(localized: "ai.error.invalidAPIKey")
        case .timeout:
            return String(localized: "ai.error.timeout")
        case .serverError(let code):
            return String(
                format: String(localized: "ai.error.server"),
                locale: AppLocalization.currentLocale,
                code
            )
        case .parsingError:
            return String(localized: "ai.error.parsing")
        case .insufficientResponses(let count):
            return String(
                format: String(localized: "ai.error.insufficientResponses"),
                locale: AppLocalization.currentLocale,
                count
            )
        case .refused(let refusal):
            return refusal.message
        }
    }
}

// MARK: - API Response Models
struct GroqResponse: Codable {
    let choices: [GroqChoice]
    let usage: GroqUsage?
    let error: GroqError?
    
    struct GroqChoice: Codable {
        let message: GroqMessage
        let finishReason: String?
        
        enum CodingKeys: String, CodingKey {
            case message
            case finishReason = "finish_reason"
        }
    }
    
    struct GroqMessage: Codable {
        let role: String
        let content: String
    }
    
    struct GroqUsage: Codable {
        let promptTokens: Int
        let completionTokens: Int
        let totalTokens: Int
        
        enum CodingKeys: String, CodingKey {
            case promptTokens = "prompt_tokens"
            case completionTokens = "completion_tokens"
            case totalTokens = "total_tokens"
        }
    }
    
    struct GroqError: Codable {
        let message: String
        let type: String
        let code: String?
    }
}

// MARK: - API Request Models
struct GroqRequest: Codable {
    let model: String
    let messages: [GroqMessage]
    let maxTokens: Int
    let temperature: Double
    let topP: Double
    let stream: Bool
    
    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case maxTokens = "max_tokens"
        case temperature
        case topP = "top_p"
        case stream
    }
    
    struct GroqMessage: Codable {
        let role: String
        let content: String
    }
}

// MARK: - AI Service Actor
actor AIService: AIServiceProtocol {
    // PROTOTYPE #12 shape A: no `Functions` as actor state; `callDictionary` gets it per call.
    private static let functionsRegion = "europe-west1"
    
    // Rate limiting
    private var requestCount = 0
    private var lastRequestTime = Date()
    private let rateLimitPerMinute = AppConfig.rateLimitPerMinute
    
    // MARK: - Initialization
    init(apiKey: String = "") {
        // API keys are owned by Firebase Functions secrets. The argument remains
        // for compatibility with older tests and call sites.
    }
    
    // MARK: - Public Methods
    func askQuestion(_ question: String, category: AICategory) async throws -> [String] {
        try await checkRateLimit()
        return try await callResponseList(
            "askAIQuestion",
            payload: basePayload([
                "question": question,
                "category": category.localizedName
            ]),
            exactCount: 3
        )
    }
    
    func suggestAnswers(for question: String) async throws -> [String] {
        try await checkRateLimit()
        return try await callResponseList(
            "suggestAIAnswers",
            payload: basePayload(["question": question]),
            exactCount: 3
        )
    }

    func suggestQuickAnswers(
        for question: String,
        category: String,
        excluding: [String] = [],
        languageName: String? = nil,
        limit: Int = 5
    ) async throws -> [String] {
        try await checkRateLimit()
        let normalizedLimit = max(1, limit)
        let aiCandidates = try await callResponseList(
            "suggestQuickAnswers",
            payload: basePayload([
                "question": question,
                "category": category,
                "excluding": excluding,
                "limit": normalizedLimit
            ], languageName: languageName),
            exactCount: nil
        )
        let merged = QuickAnswerSuggestionResolver.merge(
            localCandidates: [],
            aiCandidates: aiCandidates,
            excluding: excluding,
            limit: normalizedLimit
        )

        guard !merged.isEmpty else {
            throw AIServiceError.insufficientResponses(aiCandidates.count)
        }

        return merged
    }

    func generateQuestionPrompt(from idea: String, category: String) async throws -> String {
        try await checkRateLimit()
        let result = try await callDictionary(
            "generateQuestionPrompt",
            payload: basePayload([
                "idea": idea,
                "category": category
            ])
        )
        guard let question = result["question"] as? String, !question.isEmpty else {
            throw AIServiceError.invalidResponse
        }
        return question
    }

    func generateQuestionVariations(from topic: String, count: Int) async throws -> [String] {
        try await checkRateLimit()
        let variations = try await callStringList(
            "generateQuestionVariations",
            payload: basePayload([
                "topic": topic,
                "count": count
            ]),
            key: "variations"
        )
        guard variations.count >= count else {
            throw AIServiceError.insufficientResponses(variations.count)
        }

        return Array(variations.prefix(count))
    }

    func generateTrioQuestionSuggestions(
        from topic: String,
        count: Int,
        excluding: [String],
        availableCategoryIDs: [String]
    ) async throws -> TrioQuestionSuggestionResult {
        try await checkRateLimit()
        let result = try await callDictionary(
            "generateTrioQuestionSuggestions",
            payload: basePayload([
                "topic": topic,
                "count": count,
                "excluding": excluding,
                "availableCategoryIds": availableCategoryIDs
            ])
        )
        guard let suggestions = result["suggestions"] as? [String],
              let suggestedCategoryID = result["suggestedCategoryId"] as? String
        else {
            throw AIServiceError.invalidResponse
        }
        guard suggestions.count >= count else {
            throw AIServiceError.insufficientResponses(suggestions.count)
        }

        return TrioQuestionSuggestionResult(
            suggestions: Array(suggestions.prefix(count)),
            suggestedCategoryID: suggestedCategoryID
        )
    }
    
    // MARK: - Private Methods
    private func checkRateLimit() async throws {
        let now = Date()
        let timeSinceLastRequest = now.timeIntervalSince(lastRequestTime)
        
        // Reset counter if more than a minute has passed
        if timeSinceLastRequest > 60 {
            requestCount = 0
        }
        
        if requestCount >= rateLimitPerMinute {
            throw AIServiceError.rateLimitExceeded
        }
        
        requestCount += 1
        lastRequestTime = now
    }
    

    private func basePayload(_ values: [String: Any], languageName: String? = nil) -> [String: Any] {
        var payload = values
        payload["languageName"] = languageName ?? AppLocalization.aiPromptLanguageName
        return payload
    }

    private func callResponseList(
        _ functionName: String,
        payload: [String: Any],
        exactCount: Int?
    ) async throws -> [String] {
        let responses = try await callStringList(functionName, payload: payload, key: "responses")
        if let exactCount, responses.count != exactCount {
            throw AIServiceError.insufficientResponses(responses.count)
        }
        return responses
    }

    private func callStringList(
        _ functionName: String,
        payload: [String: Any],
        key: String
    ) async throws -> [String] {
        let result = try await callDictionary(functionName, payload: payload)
        guard let values = result[key] as? [Any] else {
            throw AIServiceError.invalidResponse
        }
        return values.compactMap { $0 as? String }
    }

    private func callDictionary(_ functionName: String, payload: [String: Any]) async throws -> [String: Any] {
        do {
            // The AI callables accept each App Check token once (functions/appCheckReplay.js), so
            // every call must ask for a fresh limited-use token instead of the cached one.
            let options = HTTPSCallableOptions(requireLimitedUseAppCheckTokens: true)
            // PROTOTYPE #12 shape A: a local callable starts in a disconnected region.
            let callable = Functions.functions(region: Self.functionsRegion)
                .httpsCallable(functionName, options: options)
            let result = try await callable.call(payload)
            guard let data = result.data as? [String: Any] else {
                throw AIServiceError.invalidResponse
            }
            return data
        } catch let error as AIServiceError {
            throw error
        } catch {
            throw mapFunctionsError(error)
        }
    }

    private func dataLossError(from nsError: NSError) -> AIServiceError {
        guard let details = nsError.userInfo[FunctionsErrorDetailsKey] as? [String: Any] else {
            return .parsingError
        }
        let reason = details["reason"] as? String
        switch reason {
        case "insufficient-responses":
            let count: Int
            if let n = details["count"] as? Int {
                count = n
            } else if let num = details["count"] as? NSNumber {
                count = num.intValue
            } else {
                count = 0
            }
            return .insufficientResponses(count)
        case "invalid-response", "empty-response":
            return .invalidResponse
        default:
            return .parsingError
        }
    }

    private func mapFunctionsError(_ error: Error) -> AIServiceError {
        let nsError = error as NSError
        guard nsError.domain == FunctionsErrorDomain else {
            if let urlError = error as? URLError, urlError.code == .timedOut {
                return .timeout
            }
            return .networkError(error)
        }
        if let refusal = CallableRefusal(nsError) {
            return .refused(refusal)
        }

        switch FunctionsErrorCode(rawValue: nsError.code) {
        case .resourceExhausted:
            return .rateLimitExceeded
        case .unauthenticated:
            if (nsError.localizedDescription.lowercased()).contains("provider key") {
                return .apiKeyInvalid
            }
            return .networkError(error)
        case .failedPrecondition:
            return .noAPIKey
        case .unavailable:
            return .serverError(503)
        case .dataLoss:
            return dataLossError(from: nsError)
        case .invalidArgument:
            return .invalidResponse
        case .deadlineExceeded:
            return .timeout
        default:
            return .networkError(error)
        }
    }
    
    // MARK: - API Key Management (deprecated - now handled by AppConfig)
    @available(*, deprecated, message: "API key is now managed by AppConfig")
    private static func loadAPIKey() -> String {
        return AppConfig.aiAPIKey ?? ""
    }
    
    // MARK: - API Key Storage (deprecated)
    @available(*, deprecated, message: "API key storage is now handled by AppConfig")
    static func setAPIKey(_ apiKey: String) {
        KeychainManager.shared.setAPIKey(apiKey)
    }
    
    @available(*, deprecated, message: "API key storage is now handled by AppConfig")
    static func clearAPIKey() {
        KeychainManager.shared.clearAPIKey()
    }
}
