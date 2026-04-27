//
//  WindowConfigurator.swift
//  SolidarityFundr
//
//  Configures the main NSWindow for edge-to-edge content with correctly
//  positioned traffic lights, matching Notes.app / Reminders.app.
//

#if os(macOS)
import AppKit

/// Sets the title bar transparent, hides the title text, and enables
/// `.fullSizeContentView` so SwiftUI content extends beneath the title bar.
///
/// IMPORTANT: We do NOT install our own `NSToolbar`. SwiftUI manages the window
/// toolbar to host `.toolbar { ToolbarItem }` items declared in views. Replacing
/// the toolbar here would clobber those items and trigger NSException crashes
/// when SwiftUI tries to update them.
///
/// We also only configure each window ONCE (tracked by associated object) —
/// `windowDidBecomeKey` fires every time a window regains focus, and
/// re-applying `.fullSizeContentView` etc. mid-session can interfere with
/// SwiftUI's window machinery.
final class WindowConfigurator: NSObject, NSApplicationDelegate {
    private static var configuredKey: UInt8 = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            self?.configureExistingWindows()
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
        configureOnce(window)
    }

    private func configureExistingWindows() {
        for window in NSApp.windows {
            configureOnce(window)
        }
    }

    private func configureOnce(_ window: NSWindow) {
        // Skip windows we've already touched. `windowDidBecomeKey` fires on
        // every focus change; one configure pass is enough.
        if objc_getAssociatedObject(window, &Self.configuredKey) != nil { return }

        // Skip windows that don't have a title bar (panels, popovers).
        guard window.styleMask.contains(.titled) else { return }

        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
        window.isMovableByWindowBackground = true

        objc_setAssociatedObject(
            window,
            &Self.configuredKey,
            true,
            .OBJC_ASSOCIATION_RETAIN_NONATOMIC
        )
    }
}
#endif
