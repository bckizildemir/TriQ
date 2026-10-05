//
//  AICategory.swift
//  TTB
//
//  Created by AI Assistant on 2025-07-18.
//

import Foundation

enum AICategory: String, CaseIterable, Codable {
    case recommendations = "Recommendations"
    case advice = "Advice"
    case learning = "Learning"
    case travel = "Travel"
    case productivity = "Productivity"
    case entertainment = "Entertainment"
    case creativity = "Creativity"
    case health = "Health"
    case career = "Career"
    case personal = "Personal"
    case other = "Other"
    
    // MARK: - Localized Names
    var localizedName: String {
        String(localized: localizedNameResource)
    }
    
    // MARK: - SF Symbols Icons
    var icon: String {
        switch self {
        case .recommendations:
            return "star.fill"
        case .advice:
            return "lightbulb.fill"
        case .learning:
            return "book.fill"
        case .travel:
            return "airplane"
        case .productivity:
            return "clock.fill"
        case .entertainment:
            return "gamecontroller.fill"
        case .creativity:
            return "paintbrush.fill"
        case .health:
            return "heart.fill"
        case .career:
            return "briefcase.fill"
        case .personal:
            return "person.fill"
        case .other:
            return "questionmark.circle"
        }
    }
    
    // MARK: - Category Colors
    var colorName: String {
        switch self {
        case .recommendations:
            return "yellow"
        case .advice:
            return "blue"
        case .learning:
            return "green"
        case .travel:
            return "purple"
        case .productivity:
            return "orange"
        case .entertainment:
            return "pink"
        case .creativity:
            return "red"
        case .health:
            return "mint"
        case .career:
            return "brown"
        case .personal:
            return "cyan"
        case .other:
            return "gray"
        }
    }
    
    // MARK: - Category Descriptions
    var description: String {
        String(localized: descriptionResource)
    }
    
    // MARK: - Sample Questions
    var sampleQuestions: [String] {
        sampleQuestionResources.map { String(localized: $0) }
    }

    private var localizedNameResource: LocalizedStringResource {
        switch self {
        case .recommendations:
            return "ai.category.recommendations.title"
        case .advice:
            return "ai.category.advice.title"
        case .learning:
            return "ai.category.learning.title"
        case .travel:
            return "ai.category.travel.title"
        case .productivity:
            return "ai.category.productivity.title"
        case .entertainment:
            return "ai.category.entertainment.title"
        case .creativity:
            return "ai.category.creativity.title"
        case .health:
            return "ai.category.health.title"
        case .career:
            return "ai.category.career.title"
        case .personal:
            return "ai.category.personal.title"
        case .other:
            return "ai.category.other.title"
        }
    }

    private var descriptionResource: LocalizedStringResource {
        switch self {
        case .recommendations:
            return "ai.category.recommendations.description"
        case .advice:
            return "ai.category.advice.description"
        case .learning:
            return "ai.category.learning.description"
        case .travel:
            return "ai.category.travel.description"
        case .productivity:
            return "ai.category.productivity.description"
        case .entertainment:
            return "ai.category.entertainment.description"
        case .creativity:
            return "ai.category.creativity.description"
        case .health:
            return "ai.category.health.description"
        case .career:
            return "ai.category.career.description"
        case .personal:
            return "ai.category.personal.description"
        case .other:
            return "ai.category.other.description"
        }
    }

    private var sampleQuestionResources: [LocalizedStringResource] {
        switch self {
        case .recommendations:
            return [
                "ai.category.recommendations.sample.1",
                "ai.category.recommendations.sample.2",
                "ai.category.recommendations.sample.3",
            ]
        case .advice:
            return [
                "ai.category.advice.sample.1",
                "ai.category.advice.sample.2",
                "ai.category.advice.sample.3",
            ]
        case .learning:
            return [
                "ai.category.learning.sample.1",
                "ai.category.learning.sample.2",
                "ai.category.learning.sample.3",
            ]
        case .travel:
            return [
                "ai.category.travel.sample.1",
                "ai.category.travel.sample.2",
                "ai.category.travel.sample.3",
            ]
        case .productivity:
            return [
                "ai.category.productivity.sample.1",
                "ai.category.productivity.sample.2",
                "ai.category.productivity.sample.3",
            ]
        case .entertainment:
            return [
                "ai.category.entertainment.sample.1",
                "ai.category.entertainment.sample.2",
                "ai.category.entertainment.sample.3",
            ]
        case .creativity:
            return [
                "ai.category.creativity.sample.1",
                "ai.category.creativity.sample.2",
                "ai.category.creativity.sample.3",
            ]
        case .health:
            return [
                "ai.category.health.sample.1",
                "ai.category.health.sample.2",
                "ai.category.health.sample.3",
            ]
        case .career:
            return [
                "ai.category.career.sample.1",
                "ai.category.career.sample.2",
                "ai.category.career.sample.3",
            ]
        case .personal:
            return [
                "ai.category.personal.sample.1",
                "ai.category.personal.sample.2",
                "ai.category.personal.sample.3",
            ]
        case .other:
            return [
                "ai.category.other.sample.1",
                "ai.category.other.sample.2",
                "ai.category.other.sample.3",
            ]
        }
    }
}

// MARK: - Category Extensions
extension AICategory {
    /// Returns the most appropriate category for a given question.
    /// Matches on whole words/prefixes rather than raw substrings, so a
    /// keyword can't match inside an unrelated larger word (adversarial
    /// hardening: malformed or adversarial question text must not force a
    /// false category match).
    static func categorize(question: String) -> AICategory {
        let questionWords = question
            .lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })

        for category in AICategory.allCases where category != .other {
            if category.matchingKeywords.contains(where: { keyword in
                containsKeyword(keyword, in: questionWords)
            }) {
                return category
            }
        }

        return .other
    }

    private static func containsKeyword(
        _ keyword: String,
        in questionWords: [Substring]
    ) -> Bool {
        let keywordWords = keyword.split(separator: " ")
        guard
            !keywordWords.isEmpty,
            keywordWords.count <= questionWords.count
        else {
            return false
        }

        for startIndex in 0...(questionWords.count - keywordWords.count) {
            let matches = keywordWords.indices.allSatisfy { offset in
                questionWords[startIndex + offset].hasPrefix(keywordWords[offset])
            }
            if matches {
                return true
            }
        }

        return false
    }

    private var matchingKeywords: [String] {
        let turkish: [String]
        let english: [String]

        switch self {
        case .recommendations:
            turkish = ["en iyi", "öner", "tavsiye et"]
            english = ["best", "recommend", "suggest"]
        case .advice:
            turkish = ["nasıl", "yol", "ipucu"]
            english = ["how", "tip", "advice"]
        case .learning:
            turkish = ["öğren", "eğitim", "ders"]
            english = ["learn", "study", "course"]
        case .travel:
            turkish = ["seyahat", "gez", "yer"]
            english = ["travel", "trip", "place"]
        case .productivity:
            turkish = ["verimli", "çalış", "zaman"]
            english = ["productive", "focus", "time"]
        case .entertainment:
            turkish = ["eğlen", "oyun", "aktivite"]
            english = ["fun", "game", "activity"]
        case .creativity:
            turkish = ["yaratıcı", "sanat", "tasarım"]
            english = ["creative", "art", "design"]
        case .health:
            turkish = ["sağlık", "egzersiz", "beslenme"]
            english = ["health", "exercise", "nutrition"]
        case .career:
            turkish = ["kariyer", "iş", "meslek"]
            english = ["career", "job", "profession"]
        case .personal:
            turkish = ["kişisel", "gelişim", "özgüven", "alışkanlık"]
            english = ["personal", "self", "habit", "confidence"]
        case .other:
            return []
        }

        return AppLocalization.prefersEnglish ? english + turkish : turkish + english
    }
}

// MARK: - Identifiable Conformance
extension AICategory: Identifiable {
    var id: String { rawValue }
}
