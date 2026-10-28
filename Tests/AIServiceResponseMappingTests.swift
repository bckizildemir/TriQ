import FirebaseFunctions
import Foundation
import Testing
@testable import TTB

/// The response and error mapping `AIService` keeps beside its callable call. `CallableRefusalTests`
/// covers `CallableRefusal` itself; this covers the rest of the path. Tested without Firebase.
struct AIServiceResponseMappingTests {
    private static func functionsError(
        _ code: FunctionsErrorCode,
        message: String = "Server text.",
        details: [String: Any]? = nil
    ) -> NSError {
        var userInfo: [String: Any] = [NSLocalizedDescriptionKey: message]
        if let details {
            userInfo[FunctionsErrorDetailsKey] = details
        }
        return NSError(domain: FunctionsErrorDomain, code: code.rawValue, userInfo: userInfo)
    }

    private static func name(of error: AIServiceError) -> String {
        switch error {
        case .invalidURL: return "invalidURL"
        case .noAPIKey: return "noAPIKey"
        case .invalidResponse: return "invalidResponse"
        case .networkError: return "networkError"
        case .rateLimitExceeded: return "rateLimitExceeded"
        case .invalidResponseFormat: return "invalidResponseFormat"
        case .emptyResponse: return "emptyResponse"
        case .apiKeyInvalid: return "apiKeyInvalid"
        case .timeout: return "timeout"
        case .serverError(let code): return "serverError(\(code))"
        case .parsingError: return "parsingError"
        case .insufficientResponses(let count): return "insufficientResponses(\(count))"
        case .refused: return "refused"
        }
    }

    // MARK: Payloads

    @Test func aDictionaryPayloadIsReturned() throws {
        let data = try AIService.dictionary(from: ["question": "Q?"])

        #expect(data["question"] as? String == "Q?")
    }

    @Test func aPayloadThatIsNotADictionaryIsInvalid() {
        #expect {
            _ = try AIService.dictionary(from: ["a", "b"])
        } throws: { error in
            (error as? AIServiceError).map(Self.name(of:)) == "invalidResponse"
        }
    }

    @Test func aStringListKeepsStringsAndDropsTheRest() throws {
        let values = try AIService.stringList(from: ["responses": ["a", 1, "b", NSNull()]], key: "responses")

        #expect(values == ["a", "b"])
    }

    @Test func aMissingOrNonArrayKeyIsInvalid() {
        for payload: [String: Any] in [[:], ["responses": "text"]] {
            #expect {
                _ = try AIService.stringList(from: payload, key: "responses")
            } throws: { error in
                (error as? AIServiceError).map(Self.name(of:)) == "invalidResponse"
            }
        }
    }

    // MARK: Data loss

    @Test func dataLossWithoutDetailsIsAParsingError() {
        let error = AIService.dataLossError(from: Self.functionsError(.dataLoss))

        #expect(Self.name(of: error) == "parsingError")
    }

    @Test func dataLossInsufficientResponsesCarriesTheCount() {
        let asInt = AIService.dataLossError(from: Self.functionsError(
            .dataLoss, details: ["reason": "insufficient-responses", "count": 2]
        ))
        let asNumber = AIService.dataLossError(from: Self.functionsError(
            .dataLoss, details: ["reason": "insufficient-responses", "count": NSNumber(value: 1)]
        ))
        let withoutCount = AIService.dataLossError(from: Self.functionsError(
            .dataLoss, details: ["reason": "insufficient-responses"]
        ))

        #expect(Self.name(of: asInt) == "insufficientResponses(2)")
        #expect(Self.name(of: asNumber) == "insufficientResponses(1)")
        #expect(Self.name(of: withoutCount) == "insufficientResponses(0)")
    }

    @Test func dataLossInvalidOrEmptyResponseIsInvalidResponse() {
        for reason in ["invalid-response", "empty-response"] {
            let error = AIService.dataLossError(from: Self.functionsError(.dataLoss, details: ["reason": reason]))

            #expect(Self.name(of: error) == "invalidResponse", "reason \(reason)")
        }
    }

    @Test func dataLossWithAnUnknownOrMissingReasonIsAParsingError() {
        let unknown = AIService.dataLossError(from: Self.functionsError(.dataLoss, details: ["reason": "other"]))
        let missing = AIService.dataLossError(from: Self.functionsError(.dataLoss, details: [:]))

        #expect(Self.name(of: unknown) == "parsingError")
        #expect(Self.name(of: missing) == "parsingError")
    }

    // MARK: Error mapping

    @Test func functionsErrorCodesMapToServiceErrors() {
        let cases: [(NSError, String)] = [
            (Self.functionsError(.resourceExhausted, details: ["reason": "daily-limit"]), "refused"),
            (Self.functionsError(.resourceExhausted), "refused"),
            (Self.functionsError(.unauthenticated, message: "The AI provider key was rejected."), "apiKeyInvalid"),
            (Self.functionsError(.failedPrecondition), "noAPIKey"),
            (Self.functionsError(.unavailable), "serverError(503)"),
            (Self.functionsError(.dataLoss, details: ["reason": "invalid-response"]), "invalidResponse"),
            (Self.functionsError(.invalidArgument), "invalidResponse"),
            (Self.functionsError(.deadlineExceeded), "timeout"),
            (Self.functionsError(.notFound), "networkError"),
        ]

        for (error, expected) in cases {
            #expect(Self.name(of: AIService.mapFunctionsError(error)) == expected, "code \(error.code)")
        }
    }

    @Test func unauthenticatedWithoutAProviderKeyMessageIsARefusal() {
        // `CallableRefusal` claims every `unauthenticated` error except the provider-key fault, so
        // the `.networkError` branch for `unauthenticated` in `mapFunctionsError` is unreachable.
        let error = Self.functionsError(.unauthenticated, message: "Something else.", details: ["reason": "other"])

        #expect(Self.name(of: AIService.mapFunctionsError(error)) == "refused")
    }

    @Test func aTimedOutURLErrorIsATimeout() {
        #expect(Self.name(of: AIService.mapFunctionsError(URLError(.timedOut))) == "timeout")
    }

    @Test func anyOtherErrorOutsideTheFunctionsDomainIsANetworkError() {
        #expect(Self.name(of: AIService.mapFunctionsError(URLError(.notConnectedToInternet))) == "networkError")
    }
}
