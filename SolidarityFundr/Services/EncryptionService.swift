//
//  EncryptionService.swift
//  SolidarityFundr
//
//  Created on 7/20/25.
//

import Foundation
import CryptoKit

class EncryptionService {
    static let shared = EncryptionService()
    private let keychainService = KeychainService()
    
    private init() {
        ensureEncryptionKey()
    }
    
    // MARK: - Key Management
    
    private func ensureEncryptionKey() {
        if !keychainService.exists(for: KeychainService.Key.encryptionKey) {
            generateAndStoreKey()
        }
    }
    
    private func generateAndStoreKey() {
        let key = SymmetricKey(size: .bits256)
        let keyData = key.withUnsafeBytes { Data($0) }
        
        do {
            try keychainService.save(keyData, for: KeychainService.Key.encryptionKey)
        } catch {
            print("Failed to store encryption key: \(error)")
        }
    }
    
    private func getKey() throws -> SymmetricKey {
        let keyData = try keychainService.retrieve(for: KeychainService.Key.encryptionKey)
        return SymmetricKey(data: keyData)
    }
    
    // MARK: - Encryption Methods
    
    func encrypt(_ string: String) throws -> Data {
        guard let data = string.data(using: .utf8) else {
            throw EncryptionError.invalidInput
        }
        return try encrypt(data)
    }
    
    func encrypt(_ data: Data) throws -> Data {
        let key = try getKey()
        let nonce = AES.GCM.Nonce()
        let sealedBox = try AES.GCM.seal(data, using: key, nonce: nonce)
        
        // Combine nonce and ciphertext for storage
        guard let combined = sealedBox.combined else {
            throw EncryptionError.encryptionFailed
        }
        
        return combined
    }
    
    func decrypt(_ data: Data) throws -> Data {
        let key = try getKey()
        let sealedBox = try AES.GCM.SealedBox(combined: data)
        return try AES.GCM.open(sealedBox, using: key)
    }
    
    func decryptToString(_ data: Data) throws -> String {
        let decryptedData = try decrypt(data)
        guard let string = String(data: decryptedData, encoding: .utf8) else {
            throw EncryptionError.decryptionFailed
        }
        return string
    }
    
    // MARK: - Secure Data Wipe
    
    func securelyWipeData(_ data: inout Data) {
        data.withUnsafeMutableBytes { bytes in
            guard let baseAddress = bytes.baseAddress else { return }
            memset_s(baseAddress, bytes.count, 0, bytes.count)
        }
    }
    
    // MARK: - Error Types
    
    enum EncryptionError: LocalizedError {
        case invalidInput
        case encryptionFailed
        case decryptionFailed
        case keyNotFound
        
        var errorDescription: String? {
            switch self {
            case .invalidInput:
                return "Invalid input data"
            case .encryptionFailed:
                return "Failed to encrypt data"
            case .decryptionFailed:
                return "Failed to decrypt data"
            case .keyNotFound:
                return "Encryption key not found"
            }
        }
    }
}

// MARK: - Secure String Extension

extension String {
    var encrypted: Data? {
        try? EncryptionService.shared.encrypt(self)
    }
}

extension Data {
    var decryptedString: String? {
        try? EncryptionService.shared.decryptToString(self)
    }
}