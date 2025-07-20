//
//  KeychainService.swift
//  SolidarityFundr
//
//  Created on 7/20/25.
//

import Foundation
import Security

class KeychainService {
    enum KeychainError: Error {
        case itemNotFound
        case duplicateItem
        case invalidData
        case unhandledError(OSStatus)
        
        var localizedDescription: String {
            switch self {
            case .itemNotFound:
                return "Item not found in keychain"
            case .duplicateItem:
                return "Item already exists in keychain"
            case .invalidData:
                return "Invalid data format"
            case .unhandledError(let status):
                return "Keychain error: \(status)"
            }
        }
    }
    
    private let service = "com.solidarityfundr.app"
    
    // MARK: - Save Data
    
    func save(_ data: Data, for key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        
        // Delete any existing item
        SecItemDelete(query as CFDictionary)
        
        // Add new item
        let status = SecItemAdd(query as CFDictionary, nil)
        
        guard status == errSecSuccess else {
            throw KeychainError.unhandledError(status)
        }
    }
    
    func save(_ string: String, for key: String) throws {
        guard let data = string.data(using: .utf8) else {
            throw KeychainError.invalidData
        }
        try save(data, for: key)
    }
    
    func save<T: Codable>(_ object: T, for key: String) throws {
        let encoder = JSONEncoder()
        let data = try encoder.encode(object)
        try save(data, for: key)
    }
    
    // MARK: - Retrieve Data
    
    func retrieve(for key: String) throws -> Data {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess else {
            if status == errSecItemNotFound {
                throw KeychainError.itemNotFound
            } else {
                throw KeychainError.unhandledError(status)
            }
        }
        
        guard let data = result as? Data else {
            throw KeychainError.invalidData
        }
        
        return data
    }
    
    func retrieveString(for key: String) throws -> String {
        let data = try retrieve(for: key)
        guard let string = String(data: data, encoding: .utf8) else {
            throw KeychainError.invalidData
        }
        return string
    }
    
    func retrieve<T: Codable>(_ type: T.Type, for key: String) throws -> T {
        let data = try retrieve(for: key)
        let decoder = JSONDecoder()
        return try decoder.decode(type, from: data)
    }
    
    // MARK: - Delete Data
    
    func delete(for key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unhandledError(status)
        }
    }
    
    // MARK: - Check Existence
    
    func exists(for key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: false
        ]
        
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        return status == errSecSuccess
    }
    
    // MARK: - Clear All
    
    func clearAll() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unhandledError(status)
        }
    }
}

// MARK: - Keychain Keys

extension KeychainService {
    enum Key {
        static let userPIN = "user_pin"
        static let biometricEnabled = "biometric_enabled"
        static let lastAuthenticationDate = "last_auth_date"
        static let sessionToken = "session_token"
        static let encryptionKey = "encryption_key"
    }
}