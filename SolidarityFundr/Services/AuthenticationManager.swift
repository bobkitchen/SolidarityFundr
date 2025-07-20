//
//  AuthenticationManager.swift
//  SolidarityFundr
//
//  Created on 7/20/25.
//

import Foundation
import LocalAuthentication
import SwiftUI

@MainActor
class AuthenticationManager: ObservableObject {
    static let shared = AuthenticationManager()
    
    @Published var isAuthenticated = false
    @Published var isLocked = true
    @Published var biometricType: LABiometryType = .none
    @Published var showingAuthError = false
    @Published var authErrorMessage = ""
    
    private let context = LAContext()
    private let keychainService = KeychainService()
    
    enum AuthenticationError: LocalizedError {
        case biometricsNotAvailable
        case biometricsNotEnrolled
        case userCancelled
        case authenticationFailed
        case passcodeNotSet
        
        var errorDescription: String? {
            switch self {
            case .biometricsNotAvailable:
                return "Biometric authentication is not available on this device"
            case .biometricsNotEnrolled:
                return "No biometric data is enrolled. Please set up Touch ID or Face ID in Settings"
            case .userCancelled:
                return "Authentication was cancelled"
            case .authenticationFailed:
                return "Authentication failed. Please try again"
            case .passcodeNotSet:
                return "Please set a device passcode to use this app"
            }
        }
    }
    
    private init() {
        checkBiometricAvailability()
    }
    
    // MARK: - Biometric Setup
    
    func checkBiometricAvailability() {
        var error: NSError?
        
        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
            biometricType = context.biometryType
        } else {
            biometricType = .none
            if let error = error {
                print("Biometric evaluation error: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - Authentication Methods
    
    func authenticate(reason: String = "Access your Solidarity Fund data") async -> Bool {
        let context = LAContext()
        var error: NSError?
        
        // Check if biometrics are available
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            await handleAuthenticationError(error)
            return false
        }
        
        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: reason
            )
            
            if success {
                isAuthenticated = true
                isLocked = false
                return true
            } else {
                return false
            }
        } catch let error as LAError {
            await handleLAError(error)
            return false
        } catch {
            authErrorMessage = error.localizedDescription
            showingAuthError = true
            return false
        }
    }
    
    func logout() {
        isAuthenticated = false
        isLocked = true
        
        // Clear any sensitive data from memory
        NotificationCenter.default.post(name: .userDidLogout, object: nil)
    }
    
    func lockApp() {
        isLocked = true
    }
    
    func unlockApp() async -> Bool {
        return await authenticate()
    }
    
    // MARK: - Error Handling
    
    private func handleAuthenticationError(_ error: NSError?) async {
        guard let error = error else {
            authErrorMessage = "Unknown authentication error"
            showingAuthError = true
            return
        }
        
        switch error.code {
        case LAError.biometryNotAvailable.rawValue:
            authErrorMessage = AuthenticationError.biometricsNotAvailable.localizedDescription ?? ""
        case LAError.biometryNotEnrolled.rawValue:
            authErrorMessage = AuthenticationError.biometricsNotEnrolled.localizedDescription ?? ""
        case LAError.passcodeNotSet.rawValue:
            authErrorMessage = AuthenticationError.passcodeNotSet.localizedDescription ?? ""
        default:
            authErrorMessage = error.localizedDescription
        }
        
        showingAuthError = true
    }
    
    private func handleLAError(_ error: LAError) async {
        switch error.code {
        case .userCancel, .systemCancel, .appCancel:
            authErrorMessage = AuthenticationError.userCancelled.localizedDescription ?? ""
        case .authenticationFailed:
            authErrorMessage = AuthenticationError.authenticationFailed.localizedDescription ?? ""
        case .biometryNotAvailable:
            authErrorMessage = AuthenticationError.biometricsNotAvailable.localizedDescription ?? ""
        case .biometryNotEnrolled:
            authErrorMessage = AuthenticationError.biometricsNotEnrolled.localizedDescription ?? ""
        case .passcodeNotSet:
            authErrorMessage = AuthenticationError.passcodeNotSet.localizedDescription ?? ""
        default:
            authErrorMessage = error.localizedDescription
        }
        
        showingAuthError = true
    }
}

// MARK: - Biometry Type Extension

extension LABiometryType {
    var displayName: String {
        switch self {
        case .none:
            return "None"
        case .touchID:
            return "Touch ID"
        case .faceID:
            return "Face ID"
        @unknown default:
            return "Unknown"
        }
    }
    
    var iconName: String {
        switch self {
        case .none:
            return "lock.fill"
        case .touchID:
            return "touchid"
        case .faceID:
            return "faceid"
        @unknown default:
            return "lock.fill"
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let userDidLogout = Notification.Name("userDidLogout")
    static let appDidLock = Notification.Name("appDidLock")
    static let appDidUnlock = Notification.Name("appDidUnlock")
}