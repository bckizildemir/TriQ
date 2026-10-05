//
//  AIProvider.swift
//  TTB
//
//  Created by AI Assistant on 2025-11-21.
//

import Foundation

/// Supported AI providers
enum AIProvider: String, CaseIterable {
    case groq
    case openrouter
    
    var displayName: String {
        switch self {
        case .groq: return "Groq"
        case .openrouter: return "OpenRouter"
        }
    }
}

/// Configuration for each AI provider
struct AIProviderConfig {
    let baseURL: String
    let defaultModel: String
    let apiKeyInfoPlistKey: String
    let headers: (String) -> [String: String]
    let validateKey: (String) -> Bool
    
    /// Get configuration for a specific provider
    static func config(for provider: AIProvider) -> AIProviderConfig {
        switch provider {
        case .groq:
            return .init(
                baseURL: "https://api.groq.com/openai/v1/chat/completions",
                defaultModel: "openai/gpt-oss-120b",
                apiKeyInfoPlistKey: "GROQ_API_KEY",
                headers: { key in
                    [
                        "Authorization": "Bearer \(key)",
                        "Content-Type": "application/json"
                    ]
                },
                validateKey: { key in
                    key.hasPrefix("gsk_") && key.count == 56
                }
            )
            
        case .openrouter:
            return .init(
                baseURL: "https://openrouter.ai/api/v1/chat/completions",
                defaultModel: "x-ai/grok-4.1-fast",
                apiKeyInfoPlistKey: "OPENROUTER_API_KEY",
                headers: { key in
                    var headers = [
                        "Authorization": "Bearer \(key)",
                        "Content-Type": "application/json"
                    ]
                    
                    // OpenRouter recommended headers
                    if let bundleId = Bundle.main.bundleIdentifier {
                        headers["HTTP-Referer"] = bundleId
                        headers["X-Title"] = "TTB"
                    }
                    
                    return headers
                },
                validateKey: { key in
                    // OpenRouter keys start with sk-or-v1-
                    key.hasPrefix("sk-or-") || key.hasPrefix("sess_or_")
                }
            )
        }
    }
}

