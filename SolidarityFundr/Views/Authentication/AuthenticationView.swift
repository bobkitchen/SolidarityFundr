//
//  AuthenticationView.swift
//  SolidarityFundr
//
//  Created on 7/20/25.
//

import SwiftUI
import LocalAuthentication

struct AuthenticationView: View {
    @StateObject private var authManager = AuthenticationManager.shared
    @State private var showingPINEntry = false
    @State private var enteredPIN = ""
    @State private var pinError = ""
    @State private var isAuthenticating = false
    @State private var pinAttempts = 0
    @State private var pinSuccess = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    var body: some View {
        ZStack {
            // Background
            LinearGradient(
                colors: [Color.blue.opacity(0.1), Color.green.opacity(0.1)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            VStack(spacing: 40) {
                // Logo and Title
                VStack(spacing: 20) {
                    Image("AvocadoLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 80, height: 80)
                    
                    Text("Parachichi House")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    Text("Solidarity Fund")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Authentication Section
                VStack(spacing: 20) {
                    if showingPINEntry {
                        pinEntryView
                    } else {
                        biometricAuthView
                    }
                }
                
                Spacer()
                
                // Security Notice
                Text("Your financial data is protected")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
        }
        .alert("Authentication Error", isPresented: $authManager.showingAuthError) {
            Button("OK") {}
        } message: {
            Text(authManager.authErrorMessage)
        }
        .sensoryFeedback(.error, trigger: pinAttempts)
        .sensoryFeedback(.success, trigger: pinSuccess)
        .onAppear {
            if !showingPINEntry {
                authenticateWithBiometrics()
            }
        }
    }
    
    // MARK: - Biometric Authentication View
    
    private var biometricAuthView: some View {
        VStack(spacing: 30) {
            Image(systemName: authManager.biometricType.iconName)
                .font(.system(size: 60))
                .foregroundColor(.accentColor)
                .symbolEffect(.pulse, options: .repeating, isActive: isAuthenticating && !reduceMotion)

            VStack(spacing: 10) {
                Text("Authentication Required")
                    .font(.headline)

                Text("Use \(authManager.biometricType.displayName) to access your fund data")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            authenticateButton
                .disabled(isAuthenticating)
            
            if PINManager.shared.hasPIN() {
                Button("Use PIN Instead") {
                    showingPINEntry = true
                }
                .font(.caption)
                .foregroundColor(.accentColor)
            }
        }
    }
    
    /// Native Liquid Glass prominent button on macOS 26+, fallback styled below.
    @ViewBuilder
    private var authenticateButton: some View {
        if #available(macOS 26.0, iOS 26.0, *) {
            Button(action: authenticateWithBiometrics) {
                Label("Authenticate", systemImage: authManager.biometricType.iconName)
                    .font(.headline)
                    .frame(width: 200)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.glassProminent)
        } else {
            Button(action: authenticateWithBiometrics) {
                Label("Authenticate", systemImage: authManager.biometricType.iconName)
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(width: 200)
                    .padding()
                    .background(Color.accentColor)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    // MARK: - PIN Entry View
    
    private var pinEntryView: some View {
        VStack(spacing: 30) {
            Image(systemName: "lock.circle.fill")
                .font(.system(size: 60))
                .foregroundColor(.accentColor)
                .symbolEffect(.bounce, value: pinAttempts)
            
            VStack(spacing: 10) {
                Text("Enter PIN")
                    .font(.headline)
                
                Text("Enter your security PIN to access the fund")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            // PIN Input
            HStack(spacing: 15) {
                ForEach(0..<6) { index in
                    Circle()
                        .fill(index < enteredPIN.count ? Color.accentColor : Color.gray.opacity(0.3))
                        .frame(width: 15, height: 15)
                }
            }
            .padding()
            
            // Number Pad
            VStack(spacing: 20) {
                ForEach(0..<3) { row in
                    HStack(spacing: 30) {
                        ForEach(1..<4) { col in
                            let number = row * 3 + col
                            numberButton(String(number))
                        }
                    }
                }
                
                HStack(spacing: 30) {
                    Button(action: {
                        showingPINEntry = false
                        enteredPIN = ""
                        pinError = ""
                    }) {
                        Image(systemName: authManager.biometricType.iconName)
                            .font(.title2)
                            .frame(width: 60, height: 60)
                            .foregroundColor(.accentColor)
                    }
                    
                    numberButton("0")
                    
                    Button(action: {
                        if !enteredPIN.isEmpty {
                            enteredPIN.removeLast()
                            pinError = ""
                        }
                    }) {
                        Image(systemName: "delete.left.fill")
                            .font(.title2)
                            .frame(width: 60, height: 60)
                            .foregroundColor(.red)
                    }
                }
            }
            
            if !pinError.isEmpty {
                Text(pinError)
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
    }
    
    // MARK: - Helper Methods
    
    @ViewBuilder
    private func numberButton(_ number: String) -> some View {
        if #available(macOS 26.0, iOS 26.0, *) {
            Button(action: { tapNumber(number) }) {
                Text(number)
                    .font(.title)
                    .frame(width: 60, height: 60)
            }
            .buttonStyle(.glass)
            .clipShape(Circle())
        } else {
            Button(action: { tapNumber(number) }) {
                Text(number)
                    .font(.title)
                    .frame(width: 60, height: 60)
                    .background(Color.gray.opacity(0.2))
                    .clipShape(RoundedRectangle(cornerRadius: 30))
            }
        }
    }

    private func tapNumber(_ number: String) {
        guard enteredPIN.count < 6 else { return }
        enteredPIN.append(number)
        if enteredPIN.count >= 4 {
            validatePIN()
        }
    }
    
    private func authenticateWithBiometrics() {
        isAuthenticating = true
        
        Task {
            let success = await authManager.authenticate()
            isAuthenticating = false
            
            if !success && authManager.biometricType == .none {
                showingPINEntry = true
            }
        }
    }
    
    private func validatePIN() {
        if PINManager.shared.verifyPIN(enteredPIN) {
            pinSuccess.toggle() // Triggers .success sensory feedback.
            authManager.authenticateWithPIN()
        } else {
            pinError = "Incorrect PIN"
            enteredPIN = ""
            pinAttempts &+= 1 // Triggers .error sensory feedback (cross-platform).
            #if os(macOS)
            NSSound.beep()
            #endif
        }
    }
}

#Preview {
    AuthenticationView()
}