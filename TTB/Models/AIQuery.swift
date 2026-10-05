//
//  AIQuery.swift
//  TTB
//
//  Created by AI Assistant on 2025-07-18.
//

import Foundation
import FirebaseFirestore

struct AIQuery: Identifiable, Codable {
    let id: String
    let question: String
    let responses: [String] // Always exactly 3 items
    let timestamp: Date
    let category: AICategory
    let isSaved: Bool
    let isLoading: Bool
    let error: String?
    
    // MARK: - Computed Properties
    // A blank/whitespace-only response is malformed AI output, not a real
    // answer — treating it as "complete" would surface an empty slot to the
    // user, so every response must be non-empty.
    var isComplete: Bool {
        responses.count == 3
            && responses.allSatisfy {
                !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            && !isLoading
            && error == nil
    }
    
    var formattedTimestamp: String {
        timestamp.formatted(
            Date.FormatStyle(date: .numeric, time: .shortened)
                .locale(AppLocalization.currentLocale)
        )
    }
    
    // MARK: - Initialization
    init(
        id: String = UUID().uuidString,
        question: String,
        responses: [String] = [],
        timestamp: Date = Date(),
        category: AICategory,
        isSaved: Bool = false,
        isLoading: Bool = false,
        error: String? = nil
    ) {
        self.id = id
        self.question = question
        self.responses = responses
        self.timestamp = timestamp
        self.category = category
        self.isSaved = isSaved
        self.isLoading = isLoading
        self.error = error
    }
    
    // MARK: - Firebase Integration
    func toFirestore() -> [String: Any] {
        return [
            "question": question,
            "responses": responses,
            "timestamp": Timestamp(date: timestamp),
            "category": category.rawValue,
            "isSaved": isSaved,
            "isLoading": isLoading,
            "error": error as Any
        ]
    }
    
    static func fromFirestore(_ data: [String: Any], id: String) -> AIQuery? {
        guard let question = data["question"] as? String,
              let responses = data["responses"] as? [String],
              let timestamp = data["timestamp"] as? Timestamp,
              let categoryString = data["category"] as? String,
              let category = AICategory(rawValue: categoryString),
              let isSaved = data["isSaved"] as? Bool,
              let isLoading = data["isLoading"] as? Bool else {
            return nil
        }
        
        let error = data["error"] as? String
        
        return AIQuery(
            id: id,
            question: question,
            responses: responses,
            timestamp: timestamp.dateValue(),
            category: category,
            isSaved: isSaved,
            isLoading: isLoading,
            error: error
        )
    }
}

// MARK: - Sample Data
extension AIQuery {
    static let sampleQueries: [AIQuery] = [
        AIQuery(
            question: "En iyi 3 Harry Potter kitabı hangisidir?",
            responses: [
                "Harry Potter ve Felsefe Taşı - Serinin başlangıcı olan bu kitap, büyülü dünyaya giriş yapmanızı sağlar.",
                "Harry Potter ve Azkaban Tutsağı - Serinin en karanlık ve olgun kitabı olarak kabul edilir.",
                "Harry Potter ve Melez Prens - Voldemort'un geçmişini derinlemesine inceleyen etkileyici bir hikaye."
            ],
            category: .recommendations,
            isSaved: false
        ),
        AIQuery(
            question: "Verimli çalışma için 3 önemli ipucu nedir?",
            responses: [
                "Pomodoro Tekniği kullanarak 25 dakika odaklanıp 5 dakika mola verin.",
                "Çalışma alanınızı düzenli ve dikkat dağıtıcı unsurlardan uzak tutun.",
                "Günlük hedeflerinizi yazılı olarak belirleyin ve öncelik sırasına koyun."
            ],
            category: .productivity,
            isSaved: true
        ),
        AIQuery(
            question: "İstanbul'da gezilecek en güzel 3 yer neresidir?",
            responses: [],
            category: .travel,
            isSaved: false,
            isLoading: true
        )
    ]
}
