//
//  PINManager.swift
//  SolidarityFundr
//
//  Created on 7/20/25.
//

import Foundation
import CommonCrypto

class PINManager {
    static let shared = PINManager()
    private let keychainService = KeychainService()

    private static let pbkdf2Iterations: UInt32 = 100_000
    private static let saltLength = 16
    private static let derivedKeyLength = 32

    private static let maxAttemptsBeforeLockout = 5
    private static let baseLockoutDuration: TimeInterval = 30

    private static let failedAttemptsKey = "pin_failed_attempts"
    private static let lockoutEndKey = "pin_lockout_end"

    private init() {}
    
    // MARK: - PIN Management
    
    func setPIN(_ pin: String) throws {
        guard isValidPIN(pin) else {
            throw PINError.invalidFormat
        }

        var salt = Data(count: PINManager.saltLength)
        let result = salt.withUnsafeMutableBytes { bufferPtr in
            SecRandomCopyBytes(kSecRandomDefault, PINManager.saltLength, bufferPtr.baseAddress!)
        }
        guard result == errSecSuccess else {
            throw PINError.invalidFormat
        }

        let hashedPIN = hashPIN(pin, salt: salt)
        try keychainService.save(salt, for: KeychainService.Key.pinSalt)
        try keychainService.save(hashedPIN, for: KeychainService.Key.userPIN)
        resetFailedAttempts()
    }
    
    func verifyPIN(_ pin: String) -> Bool {
        guard !isLockedOut() else {
            return false
        }

        guard let storedHash = try? keychainService.retrieve(for: KeychainService.Key.userPIN),
              let salt = try? keychainService.retrieve(for: KeychainService.Key.pinSalt) else {
            return false
        }

        let inputHash = hashPIN(pin, salt: salt)
        let match = constantTimeCompare(inputHash, storedHash)

        if match {
            resetFailedAttempts()
        } else {
            recordFailedAttempt()
        }

        return match
    }

    func isLockedOut() -> Bool {
        let lockoutEnd = UserDefaults.standard.double(forKey: PINManager.lockoutEndKey)
        guard lockoutEnd > 0 else { return false }
        return Date().timeIntervalSince1970 < lockoutEnd
    }
    
    func hasPIN() -> Bool {
        return keychainService.exists(for: KeychainService.Key.userPIN)
    }
    
    func removePIN() throws {
        try keychainService.delete(for: KeychainService.Key.userPIN)
        try keychainService.delete(for: KeychainService.Key.pinSalt)
        resetFailedAttempts()
    }
    
    // MARK: - Validation
    
    func isValidPIN(_ pin: String) -> Bool {
        // PIN should be 4-6 digits
        let pinRegex = "^[0-9]{4,6}$"
        let pinPredicate = NSPredicate(format: "SELF MATCHES %@", pinRegex)
        return pinPredicate.evaluate(with: pin)
    }
    
    // MARK: - Security

    private func hashPIN(_ pin: String, salt: Data) -> Data {
        var derivedKey = Data(count: PINManager.derivedKeyLength)
        _ = derivedKey.withUnsafeMutableBytes { derivedKeyPtr in
            salt.withUnsafeBytes { saltPtr in
                CCKeyDerivationPBKDF(
                    CCPBKDFAlgorithm(kCCPBKDF2),
                    pin, pin.utf8.count,
                    saltPtr.baseAddress?.assumingMemoryBound(to: UInt8.self), salt.count,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                    PINManager.pbkdf2Iterations,
                    derivedKeyPtr.baseAddress?.assumingMemoryBound(to: UInt8.self), PINManager.derivedKeyLength
                )
            }
        }
        return derivedKey
    }

    private func constantTimeCompare(_ a: Data, _ b: Data) -> Bool {
        guard a.count == b.count else { return false }
        var result: UInt8 = 0
        for (x, y) in zip(a, b) {
            result |= x ^ y
        }
        return result == 0
    }

    private func recordFailedAttempt() {
        let attempts = UserDefaults.standard.integer(forKey: PINManager.failedAttemptsKey) + 1
        UserDefaults.standard.set(attempts, forKey: PINManager.failedAttemptsKey)
        if attempts >= PINManager.maxAttemptsBeforeLockout {
            let multiplier = max(1, attempts / PINManager.maxAttemptsBeforeLockout)
            let lockoutDuration = PINManager.baseLockoutDuration * pow(2.0, Double(multiplier - 1))
            let lockoutEnd = Date().timeIntervalSince1970 + lockoutDuration
            UserDefaults.standard.set(lockoutEnd, forKey: PINManager.lockoutEndKey)
        }
    }

    private func resetFailedAttempts() {
        UserDefaults.standard.removeObject(forKey: PINManager.failedAttemptsKey)
        UserDefaults.standard.removeObject(forKey: PINManager.lockoutEndKey)
    }
    
    // MARK: - Error Types
    
    enum PINError: LocalizedError {
        case invalidFormat
        case mismatch
        case notSet
        case lockedOut

        var errorDescription: String? {
            switch self {
            case .invalidFormat:
                return "PIN must be 4-6 digits"
            case .mismatch:
                return "Incorrect PIN"
            case .notSet:
                return "No PIN has been set"
            case .lockedOut:
                return "Too many failed attempts. Please try again later"
            }
        }
    }
}