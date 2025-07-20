//
//  SecuritySettingsView.swift
//  SolidarityFundr
//
//  Created on 7/20/25.
//

import SwiftUI
import LocalAuthentication

struct SecuritySettingsView: View {
    @StateObject private var authManager = AuthenticationManager.shared
    @State private var showingPINSetup = false
    @State private var showingChangePIN = false
    @State private var showingRemovePIN = false
    @State private var biometricEnabled = true
    @State private var autoLockTimeout = 5 // minutes
    
    private let autoLockOptions = [1, 5, 15, 30, 60]
    
    var body: some View {
        Form {
            // Biometric Authentication
            Section("Biometric Authentication") {
                if authManager.biometricType != .none {
                    Toggle(isOn: $biometricEnabled) {
                        Label("\(authManager.biometricType.displayName)", systemImage: authManager.biometricType.iconName)
                    }
                    .onChange(of: biometricEnabled) { oldValue, newValue in
                        saveBiometricPreference(newValue)
                    }
                    
                    Text("Use \(authManager.biometricType.displayName) to quickly and securely access your fund data")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text("Biometric authentication not available")
                            .foregroundColor(.secondary)
                    }
                    .font(.caption)
                }
            }
            
            // PIN Management
            Section("PIN Security") {
                if PINManager.shared.hasPIN() {
                    Button(action: { showingChangePIN = true }) {
                        Label("Change PIN", systemImage: "lock.rotation")
                    }
                    
                    Button(action: { showingRemovePIN = true }) {
                        Label("Remove PIN", systemImage: "lock.slash")
                            .foregroundColor(.red)
                    }
                } else {
                    Button(action: { showingPINSetup = true }) {
                        Label("Set Up PIN", systemImage: "lock.circle")
                    }
                    
                    Text("A PIN provides an alternative way to authenticate when biometrics are unavailable")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            // Auto-Lock Settings
            Section("Auto-Lock") {
                Picker("Lock After", selection: $autoLockTimeout) {
                    ForEach(autoLockOptions, id: \.self) { minutes in
                        if minutes == 1 {
                            Text("1 minute").tag(minutes)
                        } else {
                            Text("\(minutes) minutes").tag(minutes)
                        }
                    }
                }
                
                Text("Automatically lock the app after a period of inactivity")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            // Security Information
            Section("Security Information") {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Data Encryption", systemImage: "lock.shield.fill")
                        .font(.subheadline)
                    Text("All sensitive data is encrypted using industry-standard encryption")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Label("Local Storage Only", systemImage: "internaldrive.fill")
                        .font(.subheadline)
                        .padding(.top, 5)
                    Text("Your financial data is stored securely on this device only")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Label("Biometric Protection", systemImage: "touchid")
                        .font(.subheadline)
                        .padding(.top, 5)
                    Text("Access is protected by your device's biometric authentication")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 5)
            }
        }
        .navigationTitle("Security Settings")
        .sheet(isPresented: $showingPINSetup) {
            PINSetupView(isPresented: $showingPINSetup)
        }
        .sheet(isPresented: $showingChangePIN) {
            ChangePINView(isPresented: $showingChangePIN)
        }
        .alert("Remove PIN", isPresented: $showingRemovePIN) {
            Button("Cancel", role: .cancel) {}
            Button("Remove", role: .destructive) {
                removePIN()
            }
        } message: {
            Text("Are you sure you want to remove your PIN? You will need to rely on biometric authentication only.")
        }
    }
    
    // MARK: - Helper Methods
    
    private func saveBiometricPreference(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: "biometric_enabled")
    }
    
    private func removePIN() {
        do {
            try PINManager.shared.removePIN()
        } catch {
            print("Error removing PIN: \(error)")
        }
    }
}

// MARK: - PIN Setup View

struct PINSetupView: View {
    @Binding var isPresented: Bool
    @State private var currentPIN = ""
    @State private var confirmPIN = ""
    @State private var step = 1
    @State private var error = ""
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 30) {
                // Header
                VStack(spacing: 10) {
                    Image(systemName: "lock.circle.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.accentColor)
                    
                    Text(step == 1 ? "Create PIN" : "Confirm PIN")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Text(step == 1 ? "Enter a 4-6 digit PIN" : "Re-enter your PIN to confirm")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 40)
                
                // PIN Display
                HStack(spacing: 15) {
                    ForEach(0..<6) { index in
                        Circle()
                            .fill(index < (step == 1 ? currentPIN.count : confirmPIN.count) ? Color.accentColor : Color.gray.opacity(0.3))
                            .frame(width: 15, height: 15)
                    }
                }
                .padding()
                
                if !error.isEmpty {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                        .transition(.opacity)
                }
                
                Spacer()
                
                // Number Pad
                numberPad
                
                Spacer()
            }
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        isPresented = false
                    }
                }
            }
        }
    }
    
    private var numberPad: some View {
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
                Button(action: {}) {
                    Color.clear
                        .frame(width: 60, height: 60)
                }
                .disabled(true)
                
                numberButton("0")
                
                Button(action: deleteLast) {
                    Image(systemName: "delete.left.fill")
                        .font(.title2)
                        .frame(width: 60, height: 60)
                        .foregroundColor(.red)
                }
            }
        }
    }
    
    private func numberButton(_ number: String) -> some View {
        Button(action: { addDigit(number) }) {
            Text(number)
                .font(.title)
                .frame(width: 60, height: 60)
                .background(Color.gray.opacity(0.2))
                .cornerRadius(30)
        }
    }
    
    private func addDigit(_ digit: String) {
        error = ""
        
        if step == 1 {
            if currentPIN.count < 6 {
                currentPIN.append(digit)
                if currentPIN.count >= 4 {
                    checkPINValidity()
                }
            }
        } else {
            if confirmPIN.count < 6 {
                confirmPIN.append(digit)
                if confirmPIN.count == currentPIN.count {
                    validatePINs()
                }
            }
        }
    }
    
    private func deleteLast() {
        if step == 1 {
            if !currentPIN.isEmpty {
                currentPIN.removeLast()
            }
        } else {
            if !confirmPIN.isEmpty {
                confirmPIN.removeLast()
            }
        }
        error = ""
    }
    
    private func checkPINValidity() {
        if currentPIN.count >= 4 {
            // Move to confirmation step
            withAnimation {
                step = 2
            }
        }
    }
    
    private func validatePINs() {
        if currentPIN == confirmPIN {
            // Save PIN
            do {
                try PINManager.shared.setPIN(currentPIN)
                isPresented = false
            } catch {
                self.error = "Failed to save PIN"
            }
        } else {
            error = "PINs don't match"
            confirmPIN = ""
        }
    }
}

// MARK: - Change PIN View

struct ChangePINView: View {
    @Binding var isPresented: Bool
    @State private var currentPIN = ""
    @State private var newPIN = ""
    @State private var confirmPIN = ""
    @State private var step = 1 // 1: verify current, 2: enter new, 3: confirm new
    @State private var error = ""
    
    var body: some View {
        NavigationStack {
            VStack {
                // Similar structure to PINSetupView but with 3 steps
                Text("Change PIN - Step \(step)")
                    .font(.title)
                
                // Implementation similar to PINSetupView
                // but with verification of current PIN first
            }
            .navigationTitle("Change PIN")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        isPresented = false
                    }
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        SecuritySettingsView()
    }
}