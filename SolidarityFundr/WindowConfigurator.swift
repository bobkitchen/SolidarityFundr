//
//  WindowConfigurator.swift
//  SolidarityFundr
//
//  Configures window for proper traffic light positioning in macOS 26
//

import SwiftUI
import AppKit

class WindowConfigurator: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Give SwiftUI time to create the window
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.configureMainWindow()
        }
    }
    
    private func configureMainWindow() {
        guard let window = NSApp.windows.first else { return }
        
        // Configure for macOS 26 Liquid Glass design
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.styleMask.insert(.fullSizeContentView)
        
        // Ensure we have the titled style mask for traffic lights
        if !window.styleMask.contains(.titled) {
            window.styleMask.insert(.titled)
        }
        
        // Configure toolbar style without creating a new toolbar
        // This prevents SwiftUI's toolbar management from conflicting
        window.toolbarStyle = .unifiedCompact
        
        // Set minimum size
        window.minSize = NSSize(width: 1200, height: 800)
        
        // Enable proper window appearance
        window.isMovableByWindowBackground = true
        window.backgroundColor = NSColor.windowBackgroundColor
    }
}