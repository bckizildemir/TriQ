import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions
import Foundation

enum ContentReleaseServiceError: LocalizedError {
    case authenticationRequired
    case adminRequired
    case missingFirestoreIndex
    case firebaseUnavailable
    case publishTimedOut
    case publishFailed
    case invalidPublishPayload
    case unknown(Error)

    var errorDescription: String? {
        switch self {
        case .authenticationRequired:
            return "Sign in with an admin account before publishing."
        case .adminRequired:
            return "Admin privileges are required to publish content updates."
        case .missingFirestoreIndex:
            return "Publish failed because a required Firestore index is not ready. Deploy indexes, wait until they finish building, then try again."
        case .firebaseUnavailable:
            return "Firebase is temporarily unavailable. Try again shortly."
        case .publishTimedOut:
            return "Publish timed out while contacting Firebase. Check Firebase logs before retrying."
        case .publishFailed:
            return "Publish failed. Check Firebase function logs for details."
        case .invalidPublishPayload:
            return "Publish failed because the release payload is invalid or too large."
        case .unknown(let error):
            return error.localizedDescription
        }
    }
}

struct ContentReleaseNotificationSendResult: Equatable {
    let attemptedCount: Int
    let successCount: Int
    let failureCount: Int
    let prunedCount: Int

    static let empty = ContentReleaseNotificationSendResult(
        attemptedCount: 0,
        successCount: 0,
        failureCount: 0,
        prunedCount: 0
    )
}

protocol ContentReleaseReading: Sendable {
    func fetchRelease(id: String) async throws -> ContentRelease?
    func fetchQuestions(ids: [String]) async throws -> [Question]
}

protocol ContentReleaseServicing: ContentReleaseReading {
    func listenToReleases(
        completion: @escaping (Result<[ContentRelease], Error>) -> Void
    ) -> any ListenerRegistration
    func publishPendingRelease(
        localizedTitle: [String: String],
        localizedBody: [String: String]
    ) async throws -> (releaseID: String?, didPublish: Bool)
    func sendTestNotification(
        localizedTitle: [String: String],
        localizedBody: [String: String]
    ) async throws -> ContentReleaseNotificationSendResult
    func fetchPendingCategories() async throws -> [Category]
    func fetchEligibleQuestions() async throws -> [Question]
    func suggestedCopy(
        categoryIDs: [String],
        questions: [Question],
        categories: [Category]
    ) -> (title: [String: String], body: [String: String])
}

final class ContentReleaseService: ContentReleaseServicing {
    // Computed, not stored: the service keeps no non-Sendable Firebase state, so it
    // is Sendable. The SDK returns the same cached instance on every call.
    private var db: Firestore { Firestore.firestore() }
    private var functions: Functions { Functions.functions(region: "europe-west1") }

    func listenToReleases(
        completion: @escaping (Result<[ContentRelease], Error>) -> Void
    ) -> any ListenerRegistration {
        db.collection("contentReleases")
            .order(by: "createdAt", descending: true)
            .addSnapshotListener { snapshot, error in
                if let error {
                    completion(.failure(error))
                    return
                }

                let releases = snapshot?.documents.map { document in
                    ContentRelease.fromFirestore(document.data(), id: document.documentID)
                } ?? []

                completion(.success(releases))
            }
    }

    func fetchRelease(id: String) async throws -> ContentRelease? {
        let snapshot = try await db.collection("contentReleases")
            .document(id)
            .getDocument()

        guard let data = snapshot.data() else { return nil }
        return ContentRelease.fromFirestore(data, id: snapshot.documentID)
    }

    func publishPendingRelease(
        localizedTitle: [String: String] = [:],
        localizedBody: [String: String] = [:]
    ) async throws -> (releaseID: String?, didPublish: Bool) {
        var payload: [String: Any] = [:]
        if !localizedTitle.isEmpty {
            payload["localizedTitle"] = localizedTitle
        }
        if !localizedBody.isEmpty {
            payload["localizedBody"] = localizedBody
        }

        let result: HTTPSCallableResult
        do {
            result = try await functions.httpsCallable("publishPendingContentRelease")
                .call(payload)
        } catch {
            throw mapPublishError(error)
        }

        let data = result.data as? [String: Any]
        return (
            releaseID: data?["releaseId"] as? String,
            didPublish: data?["didPublish"] as? Bool ?? false
        )
    }

    func sendTestNotification(
        localizedTitle: [String: String],
        localizedBody: [String: String]
    ) async throws -> ContentReleaseNotificationSendResult {
        let result: HTTPSCallableResult
        do {
            result = try await functions.httpsCallable("sendTestContentReleaseNotification")
                .call([
                    "localizedTitle": localizedTitle,
                    "localizedBody": localizedBody,
                ])
        } catch {
            throw mapPublishError(error)
        }

        guard let data = result.data as? [String: Any] else {
            return .empty
        }

        return ContentReleaseNotificationSendResult(
            attemptedCount: Self.intValue(data["attemptedCount"]),
            successCount: Self.intValue(data["successCount"]),
            failureCount: Self.intValue(data["failureCount"]),
            prunedCount: Self.intValue(data["prunedCount"])
        )
    }

    func fetchPendingCategories() async throws -> [Category] {
        let snapshot = try await db.collection("categories")
            .whereField("isAnnounced", isEqualTo: false)
            .getDocuments()

        return snapshot.documents
            .map { document in
                Category.fromFirestore(document.data(), id: document.documentID)
            }
            .sorted {
                if $0.sortOrder != $1.sortOrder {
                    return $0.sortOrder < $1.sortOrder
                }

                return $0.id < $1.id
            }
    }

    func fetchEligibleQuestions() async throws -> [Question] {
        let snapshot = try await db.collection("questions")
            .whereField("source", isEqualTo: QuestionSource.seeded.rawValue)
            .whereField("isAnnounced", isEqualTo: false)
            .order(by: "createdAt", descending: true)
            .getDocuments()

        return snapshot.documents.compactMap { document in
            Question.fromFirestore(document.data(), id: document.documentID)
        }
    }

    func fetchQuestions(ids: [String]) async throws -> [Question] {
        let uniqueIDs = Array(Set(ids))
        guard !uniqueIDs.isEmpty else { return [] }

        var questions: [Question] = []
        for chunk in uniqueIDs.chunked(into: 10) {
            let snapshot = try await db.collection("questions")
                .whereField(FieldPath.documentID(), in: chunk)
                .getDocuments()

            questions.append(
                contentsOf: snapshot.documents.compactMap { document in
                    Question.fromFirestore(document.data(), id: document.documentID)
                }
            )
        }

        let byID = Dictionary(uniqueKeysWithValues: questions.map { ($0.id, $0) })
        return ids.compactMap { byID[$0] }
    }

    func suggestedCopy(
        categoryIDs: [String],
        questions: [Question],
        categories: [Category]
    ) -> (title: [String: String], body: [String: String]) {
        let uniqueCategoryNamesEN = categoryIDs.compactMap { id in
            categories.first(where: { $0.id == id })?.displayName(preferredLanguageCodes: ["en"])
        }
        let uniqueCategoryNamesTR = categoryIDs.compactMap { id in
            categories.first(where: { $0.id == id })?.displayName(preferredLanguageCodes: ["tr"])
        }

        let questionCount = questions.count
        let categoryCount = categoryIDs.count

        let enTitle: String
        let trTitle: String

        switch (categoryCount, questionCount) {
        case (0, let q) where q > 0:
            enTitle = q == 1 ? "1 new question is live" : "\(q) new questions are live"
            trTitle = q == 1 ? "1 yeni soru yayında" : "\(q) yeni soru yayında"
        case (_, 0):
            enTitle = categoryCount == 1 ? "A new category is live" : "\(categoryCount) new categories are live"
            trTitle = categoryCount == 1 ? "Yeni bir kategori yayında" : "\(categoryCount) yeni kategori yayında"
        default:
            enTitle = "Fresh prompts just landed"
            trTitle = "Yeni sorular seni bekliyor"
        }

        let enBody: String
        let trBody: String

        if !uniqueCategoryNamesEN.isEmpty, questionCount > 0 {
            enBody = "Explore \(uniqueCategoryNamesEN.joined(separator: ", ")) and discover \(questionCount) fresh question\(questionCount == 1 ? "" : "s")."
            trBody = "\(uniqueCategoryNamesTR.joined(separator: ", ")) kategorilerinde \(questionCount) yeni soru seni bekliyor."
        } else if !uniqueCategoryNamesEN.isEmpty {
            enBody = "Explore \(uniqueCategoryNamesEN.joined(separator: ", ")) in the app."
            trBody = "\(uniqueCategoryNamesTR.joined(separator: ", ")) kategorilerini uygulamada keşfet."
        } else {
            enBody = "Open the app to see the latest curated questions."
            trBody = "En yeni özenle seçilmiş soruları görmek için uygulamayı aç."
        }

        return (
            title: ["en": enTitle, "tr": trTitle],
            body: ["en": enBody, "tr": trBody]
        )
    }

    private func mapPublishError(_ error: Error) -> Error {
        let nsError = error as NSError
        guard nsError.domain == FunctionsErrorDomain else {
            return ContentReleaseServiceError.unknown(error)
        }

        switch FunctionsErrorCode(rawValue: nsError.code) {
        case .unauthenticated:
            return ContentReleaseServiceError.authenticationRequired
        case .permissionDenied:
            return ContentReleaseServiceError.adminRequired
        case .failedPrecondition:
            return ContentReleaseServiceError.missingFirestoreIndex
        case .unavailable:
            return ContentReleaseServiceError.firebaseUnavailable
        case .deadlineExceeded:
            return ContentReleaseServiceError.publishTimedOut
        case .invalidArgument:
            return ContentReleaseServiceError.invalidPublishPayload
        case .internal:
            return ContentReleaseServiceError.publishFailed
        default:
            return ContentReleaseServiceError.unknown(error)
        }
    }

    private static func intValue(_ value: Any?) -> Int {
        if let int = value as? Int {
            return int
        }

        if let number = value as? NSNumber {
            return number.intValue
        }

        return 0
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0 ..< Swift.min($0 + size, count)])
        }
    }
}
