//
//  DesignSystem.swift
//  SolidarityFundr
//
//  Created on 7/20/25.
//  Central design system for Liquid Glass UI - macOS 26 Tahoe HIG Compliant
//

import Foundation
import SwiftUI

/// Central design system for consistent spacing, typography, colors, and animations
/// Updated for macOS 26 Tahoe Human Interface Guidelines with native Liquid Glass support
struct DesignSystem {

    // MARK: - macOS 26 Native Glass Materials (Legacy - prefer native glassEffect modifier)
    /// Note: For new views, use the native .glassEffect() modifier instead
    static let glassPrimary: Material = .regularMaterial
    static let glassSecondary: Material = .thinMaterial
    static let glassOverlay: Material = .ultraThinMaterial
    static let glassProminent: Material = .thickMaterial

    // MARK: - Spacing System (8pt baseline grid)
    static let marginLarge: CGFloat = 32       // Major sections
    static let marginStandard: CGFloat = 24    // Standard margins
    static let spacingXLarge: CGFloat = 24     // Major sections
    static let spacingLarge: CGFloat = 20      // Large spacing
    static let spacingMedium: CGFloat = 16     // Medium spacing
    static let spacingSmall: CGFloat = 12      // Small spacing
    static let spacingXSmall: CGFloat = 8      // Extra small spacing
    static let spacingTiny: CGFloat = 4        // Tiny spacing (increased from 2 for macOS 26)

    // MARK: - Corner Radius System (macOS 26 updated - HIG compliant)
    // Uses continuous corner style (.continuous) for Apple's squircle aesthetic
    // Values match Apple's Reminders/Notes app proportions
    static let cornerRadiusXLarge: CGFloat = 20  // Hero cards, large panels
    static let cornerRadiusLarge: CGFloat = 16   // Metric cards, main cards
    static let cornerRadiusMedium: CGFloat = 12  // Sections, secondary cards
    static let cornerRadiusSmall: CGFloat = 10   // Buttons, controls
    static let cornerRadiusXSmall: CGFloat = 8   // Nav items/badges

    // MARK: - Control Sizes (macOS 26 - taller controls)
    struct ControlSize {
        static let buttonHeightMini: CGFloat = 20
        static let buttonHeightSmall: CGFloat = 24
        static let buttonHeightMedium: CGFloat = 30  // Default - taller in macOS 26
        static let buttonHeightLarge: CGFloat = 38
        static let buttonHeightExtraLarge: CGFloat = 48  // New in macOS 26
    }

    // MARK: - Shadow System
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

    // MARK: - Animation System (macOS 26 motion guidelines)
    static let gentleSpring = Animation.spring(response: 0.5, dampingFraction: 0.8)
    static let subtleSpring = Animation.spring(response: 0.4, dampingFraction: 0.9)
    static let quickFade = Animation.easeOut(duration: 0.2)
    static let slowFade = Animation.easeInOut(duration: 0.3)
    static let interactiveSpring = Animation.spring(response: 0.35, dampingFraction: 0.7)

    // MARK: - Typography Hierarchy
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

    // MARK: - Layout Constants
    static let sidebarExpandedWidth: CGFloat = 220
    static let sidebarCollapsedWidth: CGFloat = 68
    static let sidebarPadding: CGFloat = 12
    static let minimumTouchTarget: CGFloat = 44
    static let toolbarItemSpacing: CGFloat = 8  // New: for ToolbarSpacer

    // MARK: - Z-Index Hierarchy
    static let zIndexBackground: Double = 0
    static let zIndexContent: Double = 1
    static let zIndexOverlay: Double = 10
    static let zIndexModal: Double = 100
    static let zIndexTooltip: Double = 1000
}

// MARK: - macOS 26 Glass Effect View Extensions

extension View {
    /// Apply glass effect with capsule shape
    /// Use this for buttons and pill-shaped controls
    @ViewBuilder
    func tahoeGlass() -> some View {
        self.background(.ultraThinMaterial)
            .clipShape(Capsule())
    }

    /// Apply glass effect with rounded rectangle
    /// Use this for cards and panels
    @ViewBuilder
    func tahoeGlassCard(cornerRadius: CGFloat = DesignSystem.cornerRadiusLarge) -> some View {
        self.background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.regularMaterial)
        )
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    /// Apply prominent glass effect for primary actions
    @ViewBuilder
    func tahoeGlassProminent(cornerRadius: CGFloat = DesignSystem.cornerRadiusSmall) -> some View {
        self.background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.thickMaterial)
        )
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    /// Apply nested/concentric corners for proper visual hierarchy
    @ViewBuilder
    func concentricCorners(radius: CGFloat = DesignSystem.cornerRadiusMedium) -> some View {
        self.clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }

    /// Apply glass styling for sidebars
    @ViewBuilder
    func sidebarGlassBackground() -> some View {
        self // No additional styling - liquidGlassSidebar handles it
    }
}

// MARK: - macOS 26 Glass Button Style

/// Glass button style
struct TahoeGlassButtonStyle: ButtonStyle {
    var isProminent: Bool = false
    var cornerRadius: CGFloat = DesignSystem.cornerRadiusSmall

    func makeBody(configuration: Configuration) -> some View {
        GlassButtonView(configuration: configuration, isProminent: isProminent, cornerRadius: cornerRadius)
    }

    struct GlassButtonView: View {
        let configuration: ButtonStyleConfiguration
        let isProminent: Bool
        let cornerRadius: CGFloat
        @State private var isHovered = false

        var body: some View {
            configuration.label
                .padding(.horizontal, DesignSystem.spacingMedium)
                .padding(.vertical, DesignSystem.spacingSmall)
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(isProminent ? .thickMaterial : .ultraThinMaterial)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Color.white.opacity(isHovered ? 0.2 : 0.1), lineWidth: 0.5)
                )
                .scaleEffect(configuration.isPressed ? 0.97 : (isHovered ? 1.02 : 1.0))
                .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isHovered)
                .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
                .onHover { hovering in
                    isHovered = hovering
                }
        }
    }
}

// MARK: - macOS 26 Glass Effect Container

/// Container for grouping multiple glass elements (required in macOS 26)
/// Glass cannot correctly sample other glass, so elements must share a container
@available(macOS 26.0, iOS 26.0, *)
struct TahoeGlassContainer<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        GlassEffectContainer {
            content
        }
    }
}

/// Fallback container for older OS versions
struct GlassContainerCompat<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        if #available(macOS 26.0, iOS 26.0, *) {
            GlassEffectContainer {
                content
            }
        } else {
            content
        }
    }
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

// MARK: - Accessibility Extensions

extension View {
    /// Add standard accessibility support for interactive controls
    func accessibleControl(label: String, hint: String? = nil) -> some View {
        self
            .accessibilityLabel(label)
            .accessibilityHint(hint ?? "")
            .accessibilityAddTraits(.isButton)
    }

    /// Add accessibility support for data display cards
    func accessibleCard(label: String, value: String) -> some View {
        self
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(label): \(value)")
    }
}