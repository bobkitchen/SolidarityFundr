//
//  DesignSystem.swift
//  SolidarityFundr
//
//  Created on 7/20/25.
//  Central design system for Liquid Glass UI
//

import Foundation
import SwiftUI

/// Central design system for consistent spacing, typography, colors, and animations
struct DesignSystem {
    // Enhanced Liquid Glass Materials
    static let glassPrimary: Material = .regularMaterial
    static let glassSecondary: Material = .thinMaterial
    static let glassOverlay: Material = .ultraThinMaterial
    static let glassProminent: Material = .thickMaterial
    
    // Refined Spacing (more breathing room)
    static let marginLarge: CGFloat = 32       // Major sections
    static let marginStandard: CGFloat = 24    // Standard margins
    static let spacingXLarge: CGFloat = 24     // Major sections
    static let spacingLarge: CGFloat = 20      // Large spacing
    static let spacingMedium: CGFloat = 16     // Medium spacing
    static let spacingSmall: CGFloat = 12      // Small spacing
    static let spacingXSmall: CGFloat = 8      // Extra small spacing
    static let spacingTiny: CGFloat = 2        // Tiny spacing
    
    // Enhanced Corner Radius System
    static let cornerRadiusXLarge: CGFloat = 16  // For hero cards
    static let cornerRadiusLarge: CGFloat = 12   // For main cards/sidebar
    static let cornerRadiusMedium: CGFloat = 10  // For sections
    static let cornerRadiusSmall: CGFloat = 8    // For buttons
    static let cornerRadiusXSmall: CGFloat = 6   // For nav items/badges
    
    // Refined Shadow System
    struct Shadow {
        let color: Color
        let radius: CGFloat
        let x: CGFloat
        let y: CGFloat
        
        init(color: Color, radius: CGFloat, x: CGFloat = 0, y: CGFloat) {
            self.color = color
            self.radius = radius
            self.x = x
            self.y = y
        }
    }
    
    static let shadowFloating = Shadow(color: .black.opacity(0.12), radius: 16, y: 8)
    static let shadowElevated = Shadow(color: .black.opacity(0.08), radius: 12, y: 4)
    static let shadowSubtle = Shadow(color: .black.opacity(0.05), radius: 8, y: 2)
    static let shadowHover = Shadow(color: .black.opacity(0.15), radius: 20, y: 10)
    
    // Gentle Animation System (to avoid glitches)
    static let gentleSpring = Animation.spring(response: 0.5, dampingFraction: 0.8)
    static let subtleSpring = Animation.spring(response: 0.4, dampingFraction: 0.9)
    static let quickFade = Animation.easeOut(duration: 0.2)
    static let slowFade = Animation.easeInOut(duration: 0.3)
    
    // Enhanced Typography Hierarchy
    struct Typography {
        // Primary hierarchy
        static let heroTitle = Font.system(size: 32, weight: .bold)
        static let pageTitle = Font.system(size: 28, weight: .semibold)
        static let sectionTitle = Font.system(size: 20, weight: .semibold)
        static let cardTitle = Font.system(size: 18, weight: .semibold)
        static let subtitle = Font.system(size: 16, weight: .medium)
        static let body = Font.system(size: 14, weight: .regular)
        static let caption = Font.system(size: 12, weight: .regular)
        static let small = Font.system(size: 11, weight: .regular)
        static let footnote = Font.system(size: 10, weight: .regular)
        
        // Specialized styles
        static let navItem = Font.system(size: 14, weight: .medium)
        static let navItemSelected = Font.system(size: 14, weight: .semibold)
        static let buttonText = Font.system(size: 14, weight: .medium)
        static let badge = Font.system(size: 10, weight: .semibold)
    }
    
    // Layout Constants
    static let sidebarExpandedWidth: CGFloat = 220
    static let sidebarCollapsedWidth: CGFloat = 68
    static let sidebarPadding: CGFloat = 12
    static let minimumTouchTarget: CGFloat = 44
    
    // Z-Index Hierarchy
    static let zIndexBackground: Double = 0
    static let zIndexContent: Double = 1
    static let zIndexOverlay: Double = 10
    static let zIndexModal: Double = 100
    static let zIndexTooltip: Double = 1000
}

// MARK: - Color Extensions

extension Color {
    // Text Colors
    static let primaryText = Color.primary
    static let secondaryText = Color.secondary
    static let tertiaryText = Color.secondary.opacity(0.6)
    
    // Background Colors
    static let primaryBackground = Color(NSColor.windowBackgroundColor)
    static let secondaryBackground = Color(NSColor.controlBackgroundColor)
    
    // Glass-specific Colors
    static let glassStroke = Color.white.opacity(0.1)
    static let hoverOverlay = Color.white.opacity(0.05)
    static let selectionOverlay = Color.accentColor.opacity(0.15)
    
    // Semantic Colors
    static let liquidBlue = Color.blue
    static let liquidGreen = Color.green
    static let liquidOrange = Color.orange
    static let liquidRed = Color.red
    static let liquidPurple = Color.purple
}