//
//  TransparentBackground.swift
//  SolidarityFundr
//
//  Created on 7/20/25.
//  Provides transparent background support for liquid glass windows
//

import SwiftUI
import AppKit

// MARK: - Visual Effect Background
struct VisualEffectBackground: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    let state: NSVisualEffectView.State
    
    init(
        material: NSVisualEffectView.Material = .sidebar,
        blendingMode: NSVisualEffectView.BlendingMode = .behindWindow,
        state: NSVisualEffectView.State = .active
    ) {
        self.material = material
        self.blendingMode = blendingMode
        self.state = state
    }
    
    func makeNSView(context: Context) -> NSVisualEffectView {
        let effectView = NSVisualEffectView()
        effectView.material = material
        effectView.blendingMode = blendingMode
        effectView.state = state
        effectView.wantsLayer = true
        return effectView
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.state = state
    }
}

// MARK: - Window Background Modifier
struct WindowBackgroundModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
        // Don't set any background - let the window handle it
        // Remove any custom corner radius modifications
    }
}

extension View {
    func liquidGlassWindowBackground() -> some View {
        self.modifier(WindowBackgroundModifier())
    }
}