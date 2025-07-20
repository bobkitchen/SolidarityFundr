//
//  SessionManager.swift
//  SolidarityFundr
//
//  Created on 7/20/25.
//

import Foundation
import SwiftUI

@MainActor
class SessionManager: ObservableObject {
    static let shared = SessionManager()
    
    @Published var lastActivityDate = Date()
    @Published var isSessionActive = true
    
    private var autoLockTimer: Timer?
    private var autoLockDuration: TimeInterval = 300 // 5 minutes default
    
    private init() {
        setupSessionManagement()
        loadAutoLockPreference()
    }
    
    // MARK: - Session Management
    
    private func setupSessionManagement() {
        // Monitor app lifecycle
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidBecomeActive),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidResignActive),
            name: NSApplication.didResignActiveNotification,
            object: nil
        )
        
        // Monitor user activity
        NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .mouseMoved, .leftMouseDown, .rightMouseDown]) { _ in
            Task { @MainActor in
                self.updateActivity()
            }
        }
        
        NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .mouseMoved, .leftMouseDown, .rightMouseDown]) { event in
            Task { @MainActor in
                self.updateActivity()
            }
            return event
        }
    }
    
    // MARK: - Activity Tracking
    
    func updateActivity() {
        lastActivityDate = Date()
        resetAutoLockTimer()
    }
    
    private func resetAutoLockTimer() {
        autoLockTimer?.invalidate()
        
        autoLockTimer = Timer.scheduledTimer(withTimeInterval: autoLockDuration, repeats: false) { _ in
            Task { @MainActor in
                self.lockSession()
            }
        }
    }
    
    // MARK: - Session Control
    
    func lockSession() {
        isSessionActive = false
        AuthenticationManager.shared.lockApp()
        autoLockTimer?.invalidate()
    }
    
    func unlockSession() async -> Bool {
        let success = await AuthenticationManager.shared.unlockApp()
        if success {
            isSessionActive = true
            updateActivity()
        }
        return success
    }
    
    func endSession() {
        isSessionActive = false
        autoLockTimer?.invalidate()
        AuthenticationManager.shared.logout()
    }
    
    // MARK: - Settings
    
    func setAutoLockDuration(_ minutes: Int) {
        autoLockDuration = TimeInterval(minutes * 60)
        UserDefaults.standard.set(minutes, forKey: "auto_lock_duration")
        resetAutoLockTimer()
    }
    
    private func loadAutoLockPreference() {
        let minutes = UserDefaults.standard.integer(forKey: "auto_lock_duration")
        if minutes > 0 {
            autoLockDuration = TimeInterval(minutes * 60)
        }
    }
    
    // MARK: - App Lifecycle
    
    @objc private func appDidBecomeActive() {
        if !isSessionActive {
            Task {
                _ = await unlockSession()
            }
        } else {
            updateActivity()
        }
    }
    
    @objc private func appDidResignActive() {
        // Optional: Lock immediately when app loses focus
        // lockSession()
    }
    
    deinit {
        autoLockTimer?.invalidate()
    }
}

// MARK: - View Modifier for Activity Tracking

struct ActivityTrackingModifier: ViewModifier {
    @StateObject private var sessionManager = SessionManager.shared
    
    func body(content: Content) -> some View {
        content
            .onTapGesture {
                sessionManager.updateActivity()
            }
            .onAppear {
                sessionManager.updateActivity()
            }
    }
}

extension View {
    func trackActivity() -> some View {
        modifier(ActivityTrackingModifier())
    }
}