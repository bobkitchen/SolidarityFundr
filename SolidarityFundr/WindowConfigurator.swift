//
//  WindowConfigurator.swift
//  SolidarityFundr
//
//  Created on 7/20/25.
//  Configures window for proper edge-to-edge layout with traffic light overlay
//

import SwiftUI
import AppKit

class WindowConfigurator: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var mainWindow: NSWindow?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Give SwiftUI time to create the window
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.configureMainWindow()
        }
    }
    
    private func configureMainWindow() {
        guard let window = NSApp.windows.first else { return }
        
        mainWindow = window
        window.delegate = self
        
        // Configure for liquid glass edge-to-edge design
        configureWindowAppearance(window)
        
        // Position window
        if window.isMainWindow {
            window.center()
        }
    }
    
    private func configureWindowAppearance(_ window: NSWindow) {
        // Basic configuration for Liquid Glass with sidebar-integrated traffic lights
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.styleMask.insert(.fullSizeContentView)
        
        // Enable window dragging by background
        window.isMovableByWindowBackground = true
        
        // Set minimum size
        window.minSize = NSSize(width: 1200, height: 800)
        
        // Set background color to clear for liquid glass effect
        window.backgroundColor = .clear
        
        // Enable vibrancy
        window.isOpaque = false
        window.hasShadow = true
    }
    
    
    // MARK: - NSWindowDelegate
    
    func windowWillClose(_ notification: Notification) {
        // Clean up if needed
    }
    
    func windowDidBecomeMain(_ notification: Notification) {
        // Reapply configuration when window becomes main
        if let window = notification.object as? NSWindow {
            configureWindowAppearance(window)
        }
    }
}