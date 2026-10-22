import Foundation
import FirebaseFirestore
import FirebaseAuth

actor AnswerProgressService {
    /// In-memory set of questionIds the current user has fully completed this session.
    private var answeredQuestions: Set<String> = []

    /// Records that a question has been fully answered (all 3 answers filled).
    /// Returns true if this is a new completion, false if already counted.
    func recordQuestionCompletion(questionId: String, category: String) async throws -> Bool {
        guard let userId = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "AnswerProgressService", code: -1,
                         userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }

        if answeredQuestions.contains(questionId) {
            return false
        }

        // Verify the current user's answer doc has 3 filled answers
        let userAnswerDoc = try await Firestore.firestore().collection("questions").document(questionId)
            .collection("userAnswers").document(userId).getDocument()
        guard let answers = userAnswerDoc.data()?["answers"] as? [String],
              answers.filter({ !$0.isEmpty }).count == 3 else {
            return false
        }

        answeredQuestions.insert(questionId)
        return true
    }

    /// Checks if the current user has previously fully answered this question.
    func wasQuestionAnswered(questionId: String) async throws -> Bool {
        guard let userId = Auth.auth().currentUser?.uid else { return false }

        let userAnswerDoc = try await Firestore.firestore().collection("questions").document(questionId)
            .collection("userAnswers").document(userId).getDocument()
        guard let answers = userAnswerDoc.data()?["answers"] as? [String] else {
            return false
        }
        return answers.filter { !$0.isEmpty }.count == 3
    }

    /// Seeds the in-memory set with questions the current user has already fully answered.
    func loadAnsweredQuestions() async throws {
        guard let userId = Auth.auth().currentUser?.uid else { return }

        let snapshot = try await Firestore.firestore().collectionGroup("userAnswers")
            .whereField("userId", isEqualTo: userId)
            .getDocuments()

        for doc in snapshot.documents {
            let questionId = Self.questionId(fromUserAnswerPath: doc.reference.path)
            guard !questionId.isEmpty else { continue }
            if let answers = doc.data()["answers"] as? [String],
               answers.filter({ !$0.isEmpty }).count == 3 {
                answeredQuestions.insert(questionId)
            }
        }
    }

    /// The id of the question that owns a `userAnswers` document, read from its path
    /// (`questions/<id>/userAnswers/<uid>`). Returns "" when the path has no parent document,
    /// as `reference.parent.parent?.documentID ?? ""` did.
    nonisolated static func questionId(fromUserAnswerPath path: String) -> String {
        let components = path.split(separator: "/")
        guard components.count >= 4 else { return "" }
        return String(components[components.count - 3])
    }
}

