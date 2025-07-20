//
//  TrafficLightOverlay.swift
//  SolidarityFundr
//
//  Created on 7/20/25.
//  Provides proper traffic light positioning for edge-to-edge windows
//

import SwiftUI
import AppKit

struct TrafficLightOverlay: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        // This view exists solely to ensure proper traffic light positioning
        // The actual positioning is handled by the window configuration
    }
}

// Window accessory for better traffic light control
struct WindowAccessoryView: View {
    var body: some View {
        GeometryReader { geometry in
            Color.clear
                .frame(height: 28) // Standard macOS title bar height
                .overlay(alignment: .topLeading) {
                    // Reserve space for traffic lights
                    HStack(spacing: 8) {
                        Circle()
                            .frame(width: 12, height: 12)
                            .opacity(0)
                        Circle()
                            .frame(width: 12, height: 12)
                            .opacity(0)
                        Circle()
                            .frame(width: 12, height: 12)
                            .opacity(0)
                    }
                    .padding(.leading, 12)
                    .padding(.top, 6)
                }
        }
    }
}

// Extension to help with window dragging
extension View {
    func windowDraggable() -> some View {
        self.overlay(
            WindowDragArea()
                .allowsHitTesting(false)
        )
    }
}

private struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = DraggableView()
        view.wantsLayer = true
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {}
    
    class DraggableView: NSView {
        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
        }
        
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
            true
        }
    }
}