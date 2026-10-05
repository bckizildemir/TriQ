//
//  KeychainManager.swift
//  TTB
//
//  Created by AI Assistant on 2025-07-18.
//

import Foundation
import os
import Security

final class KeychainManager: Sendable {
    static let shared = KeychainManager()
    
    private let service = "com.ttb.app"
    private let apiKeyAccount = "groq-api-key"
    private let installationIDAccount = "notification-installation-id"
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.ttb.app",
        category: "Keychain")
    
    private init() {}
    
    // MARK: - API Key Management
    func setAPIKey(_ apiKey: String) {
        let data = Data(apiKey.utf8)
        
        // Create query
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: apiKeyAccount,
            kSecValueData as String: data
        ]
        
        // Delete existing item if it exists
        SecItemDelete(query as CFDictionary)
        
        // Add new item
        let status = SecItemAdd(query as CFDictionary, nil)
        
        if status != errSecSuccess {
            logger.error("Error storing API key in keychain: \(status)")
        }
    }
    
    func getAPIKey() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: apiKeyAccount,
            kSecReturnData as String: kCFBooleanTrue!,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var dataTypeRef: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)
        
        if status == errSecSuccess {
            if let data = dataTypeRef as? Data {
                return String(data: data, encoding: .utf8)
            }
        }
        
        return nil
    }
    
    func clearAPIKey() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: apiKeyAccount
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        
        if status != errSecSuccess && status != errSecItemNotFound {
            logger.error("Error deleting API key from keychain: \(status)")
        }
    }
    
    // MARK: - Helper Methods
    func hasAPIKey() -> Bool {
        return getAPIKey() != nil
    }

    func installationIdentifier() -> String {
        if let existing = getValue(forAccount: installationIDAccount) {
            return existing
        }

        let identifier = UUID().uuidString
        setValue(identifier, forAccount: installationIDAccount)
        return identifier
    }
    
    func validateAPIKey(_ apiKey: String) -> Bool {
        // Basic validation - Groq API keys typically start with "gsk_" and are 56 characters long
        return apiKey.hasPrefix("gsk_") && apiKey.count == 56
    }

    private func setValue(_ value: String, forAccount account: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data
        ]

        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)

        if status != errSecSuccess {
            logger.error("Error storing keychain value for \(account): \(status)")
        }
    }

    private func getValue(forAccount account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: kCFBooleanTrue as Any,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var dataTypeRef: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)
        guard status == errSecSuccess, let data = dataTypeRef as? Data else {
            return nil
        }

        return String(data: data, encoding: .utf8)
    }
}

// MARK: - Error Handling
extension KeychainManager {
    enum KeychainError: LocalizedError {
        case unexpectedPasswordData
        case unhandledError(status: OSStatus)
        
        var errorDescription: String? {
            switch self {
            case .unexpectedPasswordData:
                return String(localized: "keychain.error.unexpectedPasswordData")
            case .unhandledError(let status):
                return String(
                    format: String(localized: "keychain.error.unhandled"),
                    locale: AppLocalization.currentLocale,
                    status
                )
            }
        }
    }
}
