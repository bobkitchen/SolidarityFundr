//
//  WindowConfigurator.swift
//  SolidarityFundr
//
//  Configures the main NSWindow for edge-to-edge content with correctly
//  positioned traffic lights, matching Notes.app / Reminders.app.
//

#if os(macOS)
import AppKit

/// Approach: keep the title bar (so traffic lights have an anchor frame), make
/// it transparent, hide the title text, enable full-size content view so SwiftUI
/// content extends beneath the title bar, and attach an empty NSToolbar so the
/// chrome height settles correctly. Using `.hiddenTitleBar` removes the chrome
/// that anchors traffic lights — that was the previously documented bug.
final class WindowConfigurator: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            self?.configureMainWindows()
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidBecomeKey(_:)),
            name: NSWindow.didBecomeKeyNotification,
            object: nil
        )
    }

    @objc private func windowDidBecomeKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        configure(window)
    }

    private func configureMainWindows() {
        for window in NSApp.windows {
            configure(window)
        }
    }

    private func configure(_ window: NSWindow) {
        // Skip windows that don't have a title bar (panels, popovers).
        guard window.styleMask.contains(.titled) else { return }

        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)

        // Attach a minimal toolbar — gives the title bar a stable height and
        // lets traffic lights settle into their canonical position.
        if window.toolbar == nil {
            let toolbar = NSToolbar(identifier: "MainToolbar")
            window.toolbar = toolbar
            window.toolbarStyle = .unified
        }

        window.isMovableByWindowBackground = true
    }
}
#endif
