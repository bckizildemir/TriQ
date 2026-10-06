import FirebaseFunctions
import Foundation

enum AnswerImageSuggestionServiceError: LocalizedError {
    case invalidResponse
    case noResults
    case serviceUnavailable(Error)
    case refused(CallableRefusal)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return AppLocalization.prefersEnglish
                ? "Image results could not be read."
                : "Görsel sonuçları okunamadı."
        case .noResults:
            return AppLocalization.prefersEnglish
                ? "No matching images found. Try a different answer."
                : "Bu cevap için uygun görsel bulamadık. Daha farklı bir ifade dene."
        case let .serviceUnavailable(error):
            return error.localizedDescription
        case let .refused(refusal):
            return refusal.message
        }
    }
}

actor AnswerImageSuggestionService {
    private let functions = Functions.functions(region: "europe-west1")

    func suggestImages(
        questionId: String,
        slotIndex: Int,
        answerText: String
    ) async throws -> [AnswerImageSuggestion] {
        let payload: [String: Any] = [
            "questionId": questionId,
            "slotIndex": slotIndex,
            "answerText": answerText,
            "locale": AppLocalization.prefersEnglish ? "en-US" : "tr-TR",
        ]

        do {
            // suggestAnswerImages accepts each App Check token once (functions/appCheckReplay.js).
            let options = HTTPSCallableOptions(requireLimitedUseAppCheckTokens: true)
            let result = try await functions.httpsCallable("suggestAnswerImages", options: options).call(payload)
            guard let data = result.data as? [String: Any],
                  let rawSuggestions = data["suggestions"] as? [Any]
            else {
                throw AnswerImageSuggestionServiceError.invalidResponse
            }

            let suggestions = rawSuggestions.compactMap(AnswerImageSuggestion.init(functionsValue:))
            guard !suggestions.isEmpty else {
                throw AnswerImageSuggestionServiceError.noResults
            }
            return suggestions
        } catch let error as AnswerImageSuggestionServiceError {
            throw error
        } catch {
            if let refusal = CallableRefusal(error as NSError) {
                throw AnswerImageSuggestionServiceError.refused(refusal)
            }
            throw AnswerImageSuggestionServiceError.serviceUnavailable(error)
        }
    }

    func saveSuggestedImage(
        _ suggestion: AnswerImageSuggestion,
        questionId: String,
        slotIndex: Int
    ) async throws -> (downloadURL: String, attribution: AnswerImageAttribution?) {
        let payload: [String: Any] = [
            "questionId": questionId,
            "slotIndex": slotIndex,
            "suggestion": suggestion.functionsPayload,
        ]

        do {
            let result = try await functions.httpsCallable("saveSuggestedAnswerImage").call(payload)
            guard let data = result.data as? [String: Any],
                  let downloadURL = data["downloadURL"] as? String
            else {
                throw AnswerImageSuggestionServiceError.invalidResponse
            }

            let attribution = AnswerImageAttribution(firestoreValue: data["attribution"] as Any)
            return (downloadURL, attribution)
        } catch let error as AnswerImageSuggestionServiceError {
            throw error
        } catch {
            if let refusal = CallableRefusal(error as NSError) {
                throw AnswerImageSuggestionServiceError.refused(refusal)
            }
            throw AnswerImageSuggestionServiceError.serviceUnavailable(error)
        }
    }
}
