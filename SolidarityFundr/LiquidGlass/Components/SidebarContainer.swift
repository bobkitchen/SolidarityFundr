//
//  SidebarContainer.swift
//  SolidarityFundr
//
//  Created on 7/20/25.
//  Container view that properly positions sidebar content with traffic lights
//

import SwiftUI

struct SidebarContainer<Content: View>: View {
    let content: Content
    
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            // Background with visual effect
            VisualEffectBackground(
                material: .sidebar,
                blendingMode: .behindWindow
            )
            .cornerRadius(DesignSystem.cornerRadiusLarge)
            
            // Content with proper padding
            VStack(spacing: 0) {
                // Traffic light area - invisible spacer
                Color.clear
                    .frame(height: 28) // Standard macOS titlebar height
                    .frame(maxWidth: .infinity)
                
                // Actual sidebar content
                content
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// Extension for easy use
extension View {
    func inSidebarContainer() -> some View {
        SidebarContainer {
            self
        }
    }
}