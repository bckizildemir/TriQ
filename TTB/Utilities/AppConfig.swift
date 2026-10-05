//
//  AppConfig.swift
//  TTB
//
//  Created by AI Assistant on 2025-07-18.
//

import Foundation
import os

struct AppConfig {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.ttb.app",
        category: "AppConfig")

    // MARK: - Onboarding & Legal
    static let onboardingVersion = 2
    static let legalVersion = "2026-03"
    static let aiTabDisclosureVersion = 1
    static let guestDailyAIQueryLimit = 5

    static var termsURL: URL? {
        url(forInfoDictionaryKey: "TERMS_URL")
    }

    static var privacyURL: URL? {
        url(forInfoDictionaryKey: "PRIVACY_URL")
    }

    // MARK: - AI Configuration
    static let maxTokens = 500
    static let temperature = 0.7
    static let topP = 1.0
    
    // MARK: - Generic AI Provider Configuration
    /// Current AI provider (Groq, OpenRouter, etc.)
    static var aiProvider: AIProvider {
        if let providerString = Bundle.main.object(forInfoDictionaryKey: "AI_PROVIDER") as? String,
           let provider = AIProvider(rawValue: providerString.lowercased()) {
            return provider
        }
        // Default to OpenRouter
        return .openrouter
    }
    
    /// API key for the current provider
    static var aiAPIKey: String? {
        let config = AIProviderConfig.config(for: aiProvider)
        let keyName = config.apiKeyInfoPlistKey
        
        guard let apiKey = Bundle.main.object(forInfoDictionaryKey: keyName) as? String,
              !apiKey.isEmpty,
              apiKey != "$(\(keyName))" else {
            
            logger.warning("\(aiProvider.displayName) API key is missing from app configuration.")
            
            return nil
        }
        return apiKey
    }
    
    /// Base URL for AI API
    static var aiBaseURL: String {
        AIProviderConfig.config(for: aiProvider).baseURL
    }
    
    /// Default model for the current provider
    static var aiModel: String {
        // Check if custom model is specified in Info.plist
        if let customModel = Bundle.main.object(forInfoDictionaryKey: "AI_MODEL") as? String,
           !customModel.isEmpty,
           customModel != "$(AI_MODEL)" {
            return customModel
        }
        
        // Return provider's default model
        return AIProviderConfig.config(for: aiProvider).defaultModel
    }
    
    /// Request headers for the current provider
    static func aiRequestHeaders() -> [String: String] {
        guard let apiKey = aiAPIKey else { return [:] }
        return AIProviderConfig.config(for: aiProvider).headers(apiKey)
    }
    
    /// Validate API key format
    static func validateAIKey(_ key: String) -> Bool {
        return AIProviderConfig.config(for: aiProvider).validateKey(key)
    }
    
    // MARK: - Legacy Groq API Key (for backward compatibility)
    @available(*, deprecated, message: "Use aiAPIKey instead")
    static var groqAPIKey: String? {
        return aiAPIKey
    }
    
    // MARK: - Rate Limiting
    static let rateLimitPerMinute = 30
    static let rateLimitPerHour = 100
    static let rateLimitPerDay = 500
    
    // MARK: - Usage Limits
    static let dailyQueryLimit = 50
    static let weeklyQueryLimit = 200
    static let monthlyQueryLimit = 500
    
    // MARK: - Cache Configuration
    static let cacheExpirationMinutes = 60
    static let maxCachedQueries = 100
    
    // MARK: - Environment Detection
    static var isDebug: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }
    
    static var isProduction: Bool {
        return !isDebug
    }
    
    // MARK: - API Key Validation (deprecated)
    @available(*, deprecated, message: "Use validateAIKey instead")
    static func validateAPIKey(_ apiKey: String) -> Bool {
        return validateAIKey(apiKey)
    }
    
    // MARK: - Feature Flags
    static let enableAICache = true
    static let enableUsageTracking = true
    static let enableOfflineMode = false
    static let enableAnalytics = true
    
    // MARK: - Logging Configuration
    static let logLevel: LogLevel = isDebug ? .debug : .error
    
    enum LogLevel: String, CaseIterable {
        case debug = "DEBUG"
        case info = "INFO"
        case warning = "WARNING"
        case error = "ERROR"
        
        var priority: Int {
            switch self {
            case .debug: return 0
            case .info: return 1
            case .warning: return 2
            case .error: return 3
            }
        }
    }
    
    // MARK: - Network Configuration
    static let networkTimeoutSeconds: TimeInterval = 30
    static let maxRetryAttempts = 3
    static let retryDelaySeconds: TimeInterval = 1
    
    // MARK: - UI Configuration
    static let animationDuration: TimeInterval = 0.3
    static let longAnimationDuration: TimeInterval = 0.6
    static let shortAnimationDuration: TimeInterval = 0.15
    
    // MARK: - Development Configuration
    #if DEBUG
    static let useMockAI = false // Set to true to use mock AI service
    static let enableDetailedLogging = true
    static let skipAPIKeyValidation = false
    #endif
}

// MARK: - Configuration Validation
extension AppConfig {
    static func validateConfiguration() -> [String] {
        var errors: [String] = []
        
        // Validate API URL
        if URL(string: aiBaseURL) == nil {
            errors.append("Invalid AI API URL")
        }
        
        // Validate API Key
        if let apiKey = aiAPIKey {
            if !validateAIKey(apiKey) {
                errors.append("Invalid \(aiProvider.displayName) API key format")
            }
        } else {
            errors.append("\(aiProvider.displayName) API key not configured")
        }
        
        // Validate rate limits
        if rateLimitPerMinute <= 0 || rateLimitPerHour <= 0 || rateLimitPerDay <= 0 {
            errors.append("Invalid rate limit configuration")
        }
        
        // Validate usage limits
        if dailyQueryLimit <= 0 || weeklyQueryLimit <= 0 || monthlyQueryLimit <= 0 {
            errors.append("Invalid usage limit configuration")
        }
        
        // Validate model parameters
        if maxTokens <= 0 || temperature < 0 || temperature > 2 || topP < 0 || topP > 1 {
            errors.append("Invalid model parameters")
        }
        
        return errors
    }
    
    static func printConfiguration() {
        logger.info("Environment: \(isDebug ? "Debug" : "Production")")
        logger.info("AI Provider: \(aiProvider.displayName)")
        logger.info("API URL: \(aiBaseURL)")
        logger.info("Model: \(aiModel)")
        logger.info("Max Tokens: \(maxTokens)")
        logger.info("Temperature: \(temperature)")
        logger.info("Daily Query Limit: \(dailyQueryLimit)")
        logger.info("Rate Limit Per Minute: \(rateLimitPerMinute)")
        logger.info("Cache Enabled: \(enableAICache)")
        logger.info("Usage Tracking: \(enableUsageTracking)")
        logger.info("Log Level: \(logLevel.rawValue)")
        logger.info("API Key Configured: \(aiAPIKey != nil)")
    }
    
    // MARK: - API Key Management (Internal)
    /// Check if the app has a valid API key configured
    static func hasValidAPIKey() -> Bool {
        guard let apiKey = aiAPIKey else { return false }
        return validateAIKey(apiKey)
    }
    
    /// Get information about API key source for debugging
    static func getAPIKeySource() -> String {
        let keyName = AIProviderConfig.config(for: aiProvider).apiKeyInfoPlistKey
        
        // Check Info.plist
        if let plistKey = Bundle.main.object(forInfoDictionaryKey: keyName) as? String,
           !plistKey.isEmpty && !plistKey.hasPrefix("$(") {
            return "Info.plist (\(keyName))"
        }
        
        // Check environment variable
        if let envKey = ProcessInfo.processInfo.environment[keyName],
           !envKey.isEmpty {
            return "Environment Variable (\(keyName))"
        }
        
        #if DEBUG
        return "Development Fallback"
        #else
        return "Not Configured"
        #endif
    }

    private static func url(forInfoDictionaryKey key: String) -> URL? {
        guard let rawValue = Bundle.main.object(forInfoDictionaryKey: key) as? String,
              !rawValue.isEmpty,
              rawValue != "$(\(key))",
              let url = URL(string: rawValue) else {
            return nil
        }
        return url
    }
}
