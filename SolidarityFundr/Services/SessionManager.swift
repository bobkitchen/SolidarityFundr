//
//  SessionManager.swift
//  SolidarityFundr
//
//  Created on 7/20/25.
//

import Foundation
import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

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
        // App lifecycle. macOS uses NSApplication notifications, iOS uses
        // UIApplication notifications — same behavioural intent (lock on
        // backgrounding, refresh activity on foregrounding).
        #if os(macOS)
        let activeName = NSApplication.didBecomeActiveNotification
        let resignName = NSApplication.didResignActiveNotification
        #else
        let activeName = UIApplication.didBecomeActiveNotification
        let resignName = UIApplication.willResignActiveNotification
        #endif

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidBecomeActive),
            name: activeName,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidResignActive),
            name: resignName,
            object: nil
        )

        // Global keyboard / mouse monitoring is macOS-only — there's no
        // iOS equivalent, and iPhones get their auto-lock behaviour from
        // OS-level backgrounding plus the in-view `.trackActivity()`
        // modifier on user-driven views.
        #if os(macOS)
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
        #endif
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
        // Lock immediately when app loses focus. Auto-lock timer alone is
        // insufficient — timers reset on any input in any app, and a user who
        // Cmd-Tabs away from a financial app should not return to an unlocked
        // session.
        lockSession()
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