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
                .opacity(isAuthenticating ? 0.5 : 1.0)
                .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: isAuthenticating)
            
            VStack(spacing: 10) {
                Text("Authentication Required")
                    .font(.headline)
                
                Text("Use \(authManager.biometricType.displayName) to access your fund data")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            Button(action: authenticateWithBiometrics) {
                Label("Authenticate", systemImage: authManager.biometricType.iconName)
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(width: 200)
                    .padding()
                    .background(Color.accentColor)
                    .cornerRadius(10)
            }
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
    
    // MARK: - PIN Entry View
    
    private var pinEntryView: some View {
        VStack(spacing: 30) {
            Image(systemName: "lock.circle.fill")
                .font(.system(size: 60))
                .foregroundColor(.accentColor)
            
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
    
    private func numberButton(_ number: String) -> some View {
        Button(action: {
            if enteredPIN.count < 6 {
                enteredPIN.append(number)
                
                if enteredPIN.count >= 4 {
                    validatePIN()
                }
            }
        }) {
            Text(number)
                .font(.title)
                .frame(width: 60, height: 60)
                .background(Color.gray.opacity(0.2))
                .cornerRadius(30)
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
            authManager.isAuthenticated = true
            authManager.isLocked = false
        } else {
            pinError = "Incorrect PIN"
            enteredPIN = ""
            
            // Add haptic feedback for error on iOS only
            #if os(iOS)
            let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
            impactFeedback.impactOccurred()
            #else
            NSSound.beep()
            #endif
        }
    }
}

#Preview {
    AuthenticationView()
}