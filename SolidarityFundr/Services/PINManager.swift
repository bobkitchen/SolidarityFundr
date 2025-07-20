//
//  PINManager.swift
//  SolidarityFundr
//
//  Created on 7/20/25.
//

import Foundation
import CryptoKit

class PINManager {
    static let shared = PINManager()
    private let keychainService = KeychainService()
    
    private init() {}
    
    // MARK: - PIN Management
    
    func setPIN(_ pin: String) throws {
        guard isValidPIN(pin) else {
            throw PINError.invalidFormat
        }
        
        let hashedPIN = hashPIN(pin)
        try keychainService.save(hashedPIN, for: KeychainService.Key.userPIN)
    }
    
    func verifyPIN(_ pin: String) -> Bool {
        guard let storedHash = try? keychainService.retrieveString(for: KeychainService.Key.userPIN) else {
            return false
        }
        
        let inputHash = hashPIN(pin)
        return inputHash == storedHash
    }
    
    func hasPIN() -> Bool {
        return keychainService.exists(for: KeychainService.Key.userPIN)
    }
    
    func removePIN() throws {
        try keychainService.delete(for: KeychainService.Key.userPIN)
    }
    
    // MARK: - Validation
    
    func isValidPIN(_ pin: String) -> Bool {
        // PIN should be 4-6 digits
        let pinRegex = "^[0-9]{4,6}$"
        let pinPredicate = NSPredicate(format: "SELF MATCHES %@", pinRegex)
        return pinPredicate.evaluate(with: pin)
    }
    
    // MARK: - Security
    
    private func hashPIN(_ pin: String) -> String {
        guard let data = pin.data(using: .utf8) else {
            return ""
        }
        
        let hashed = SHA256.hash(data: data)
        return hashed.compactMap { String(format: "%02x", $0) }.joined()
    }
    
    // MARK: - Error Types
    
    enum PINError: LocalizedError {
        case invalidFormat
        case mismatch
        case notSet
        
        var errorDescription: String? {
            switch self {
            case .invalidFormat:
                return "PIN must be 4-6 digits"
            case .mismatch:
                return "Incorrect PIN"
            case .notSet:
                return "No PIN has been set"
            }
        }
    }
}