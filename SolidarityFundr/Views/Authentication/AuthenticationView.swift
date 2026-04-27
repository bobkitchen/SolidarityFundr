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
                        .foregroundStyle(.secondary)
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
                    .foregroundStyle(.secondary)
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
                .foregroundStyle(Color.accentColor)
                .symbolEffect(.pulse, options: .repeating, isActive: isAuthenticating && !reduceMotion)

            VStack(spacing: 10) {
                Text("Authentication Required")
                    .font(.headline)

                Text("Use \(authManager.biometricType.displayName) to access your fund data")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            authenticateButton
                .disabled(isAuthenticating)
            
            if PINManager.shared.hasPIN() {
                Button("Use PIN Instead") {
                    showingPINEntry = true
                }
                .font(.caption)
                .foregroundStyle(Color.accentColor)
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
                    .foregroundStyle(.white)
                    .frame(width: 200)
                    .padding()
                    .background(Color.accentColor)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    // MARK: - PIN Entry View
    //
    // macOS users have a keyboard — the number-pad pattern is an iOS idiom.
    // On Mac we use a single SecureField that auto-validates as the user
    // types. iOS keeps the number pad.

    private var pinEntryView: some View {
        VStack(spacing: 24) {
            Image(systemName: "lock.circle.fill")
                .font(.system(size: 60))
                .foregroundStyle(Color.accentColor)
                .symbolEffect(.bounce, value: pinAttempts)

            VStack(spacing: 8) {
                Text("Enter PIN")
                    .font(.headline)
                Text("Enter your security PIN to access the fund")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            #if os(macOS)
            macPINField
            #else
            iOSPINPad
            #endif

            if !pinError.isEmpty {
                Text(pinError)
                    .font(.callout)
                    .foregroundStyle(.red)
            }

            if authManager.biometricType != .none {
                Button("Use \(authManager.biometricType.displayName) Instead") {
                    showingPINEntry = false
                    enteredPIN = ""
                    pinError = ""
                    authenticateWithBiometrics()
                }
                .buttonStyle(.link)
            }
        }
        .frame(maxWidth: 320)
    }

    #if os(macOS)
    @ViewBuilder
    private var macPINField: some View {
        VStack(spacing: 12) {
            SecureField("PIN", text: $enteredPIN)
                .textFieldStyle(.roundedBorder)
                .controlSize(.large)
                .multilineTextAlignment(.center)
                .font(.title2.monospacedDigit())
                .frame(maxWidth: 200)
                .onSubmit { validatePIN() }
                .onChange(of: enteredPIN) { _, value in
                    // Limit to 6 digits, strip non-digits
                    let digitsOnly = value.filter(\.isNumber).prefix(6)
                    if String(digitsOnly) != value {
                        enteredPIN = String(digitsOnly)
                    }
                    pinError = ""
                }

            Button("Unlock") { validatePIN() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .disabled(enteredPIN.count < 4)
        }
    }
    #else
    @ViewBuilder
    private var iOSPINPad: some View {
        VStack(spacing: 24) {
            // Six-dot indicator
            HStack(spacing: 16) {
                ForEach(0..<6, id: \.self) { index in
                    Circle()
                        .fill(index < enteredPIN.count ? Color.accentColor : .secondary.opacity(0.3))
                        .frame(width: 14, height: 14)
                }
            }

            VStack(spacing: 16) {
                ForEach(0..<3, id: \.self) { row in
                    HStack(spacing: 24) {
                        ForEach(1..<4, id: \.self) { col in
                            numberButton(String(row * 3 + col))
                        }
                    }
                }
                HStack(spacing: 24) {
                    Color.clear.frame(width: 60, height: 60)
                    numberButton("0")
                    Button {
                        if !enteredPIN.isEmpty {
                            enteredPIN.removeLast()
                            pinError = ""
                        }
                    } label: {
                        Image(systemName: "delete.left.fill")
                            .font(.title2)
                            .frame(width: 60, height: 60)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func numberButton(_ number: String) -> some View {
        Button { tapNumber(number) } label: {
            Text(number)
                .font(.title)
                .frame(width: 60, height: 60)
                .background(.thinMaterial, in: Circle())
        }
        .buttonStyle(.plain)
    }

    private func tapNumber(_ number: String) {
        guard enteredPIN.count < 6 else { return }
        enteredPIN.append(number)
        if enteredPIN.count >= 4 {
            validatePIN()
        }
    }
    #endif
    
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