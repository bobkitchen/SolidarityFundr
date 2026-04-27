//
//  LiquidGlassMaterial.swift
//  SolidarityFundr
//
//  Created on 7/20/25.
//  Liquid Glass Design System for macOS 26 Tahoe - HIG Compliant
//

import SwiftUI

// MARK: - Liquid Glass Material Protocol

protocol LiquidGlassMaterial {
    var transparency: Double { get }
    var blurRadius: Double { get }
    var tintColor: Color? { get }
    var specularIntensity: Double { get }
    var thickness: MaterialThickness { get }
}

// MARK: - Material Thickness

enum MaterialThickness: Double, CaseIterable {
    case ultraThin = 0.2
    case thin = 0.4
    case regular = 0.6
    case thick = 0.8
    case ultraThick = 1.0

    var blurMultiplier: Double {
        return rawValue
    }

    var opacityValue: Double {
        return 1.0 - (rawValue * 0.15)
    }

    /// Map to native SwiftUI Material for fallback
    var nativeMaterial: Material {
        switch self {
        case .ultraThin: return .ultraThinMaterial
        case .thin: return .thinMaterial
        case .regular: return .regularMaterial
        case .thick: return .thickMaterial
        case .ultraThick: return .ultraThickMaterial
        }
    }
}

// MARK: - macOS 26 Native Glass Material Modifier

/// Primary glass material using macOS 26 native glassEffect
/// Falls back to traditional material for older OS versions
struct PrimaryGlassMaterial: ViewModifier, LiquidGlassMaterial {
    let transparency: Double = 0.85
    let blurRadius: Double = 12
    let tintColor: Color? = nil
    let specularIntensity: Double = 0.8
    let thickness: MaterialThickness = .regular
    var cornerRadius: CGFloat = DesignSystem.cornerRadiusXLarge

    @Environment(\.colorScheme) var colorScheme

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    private var glassTint: Color {
        if let tintColor = tintColor {
            return tintColor
        }
        return colorScheme == .dark ? .white : .black
    }
}

// MARK: - Secondary Glass Material

struct SecondaryGlassMaterial: ViewModifier, LiquidGlassMaterial {
    let transparency: Double = 0.75
    let blurRadius: Double = 8
    let tintColor: Color? = nil
    let specularIntensity: Double = 0.6
    let thickness: MaterialThickness = .thin
    var cornerRadius: CGFloat = DesignSystem.cornerRadiusLarge

    @Environment(\.colorScheme) var colorScheme

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.regularMaterial)
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    private var glassTint: Color {
        if let tintColor = tintColor {
            return tintColor
        }
        return colorScheme == .dark ? .white : .black
    }
}

// MARK: - Tertiary Glass Material

struct TertiaryGlassMaterial: ViewModifier, LiquidGlassMaterial {
    let transparency: Double = 0.65
    let blurRadius: Double = 4
    let tintColor: Color? = nil
    let specularIntensity: Double = 0.4
    let thickness: MaterialThickness = .ultraThin
    var cornerRadius: CGFloat = DesignSystem.cornerRadiusMedium

    @Environment(\.colorScheme) var colorScheme

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.thinMaterial)
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    private var glassTint: Color {
        if let tintColor = tintColor {
            return tintColor
        }
        return colorScheme == .dark ? .white : .black
    }
}

// MARK: - View Extensions

extension View {
    /// Apply primary glass material (macOS 26 native or fallback)
    func primaryGlass(cornerRadius: CGFloat = DesignSystem.cornerRadiusXLarge) -> some View {
        self.modifier(PrimaryGlassMaterial(cornerRadius: cornerRadius))
    }

    /// Apply secondary glass material (macOS 26 native or fallback)
    func secondaryGlass(cornerRadius: CGFloat = DesignSystem.cornerRadiusLarge) -> some View {
        self.modifier(SecondaryGlassMaterial(cornerRadius: cornerRadius))
    }

    /// Apply tertiary glass material (macOS 26 native or fallback)
    func tertiaryGlass(cornerRadius: CGFloat = DesignSystem.cornerRadiusMedium) -> some View {
        self.modifier(TertiaryGlassMaterial(cornerRadius: cornerRadius))
    }
}

// MARK: - macOS 26 Adaptive Glass Material

struct AdaptiveGlassMaterial: ViewModifier {
    let style: GlassStyle
    @State private var adaptiveBlurRadius: Double = 8
    @State private var adaptiveTint: Color = .clear

    enum GlassStyle {
        case primary, secondary, tertiary, custom(transparency: Double, blur: Double)

        var cornerRadius: CGFloat {
            switch self {
            case .primary: return DesignSystem.cornerRadiusXLarge
            case .secondary: return DesignSystem.cornerRadiusLarge
            case .tertiary: return DesignSystem.cornerRadiusMedium
            case .custom: return DesignSystem.cornerRadiusLarge
            }
        }
    }

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous)
                    .fill(material)
            )
            .clipShape(RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous))
    }

    private var material: Material {
        switch style {
        case .primary: return .ultraThinMaterial
        case .secondary: return .regularMaterial
        case .tertiary: return .thinMaterial
        case .custom: return .ultraThinMaterial
        }
    }

    private var tintOpacity: Double {
        switch style {
        case .primary: return 0.05
        case .secondary: return 0.08
        case .tertiary: return 0.12
        case .custom(let transparency, _): return (1 - transparency) * 0.2
        }
    }

    private var shadowColor: Color {
        return .black.opacity(shadowOpacity)
    }

    private var shadowOpacity: Double {
        switch style {
        case .primary: return 0.1
        case .secondary: return 0.08
        case .tertiary: return 0.05
        case .custom: return 0.08
        }
    }

    private var shadowRadius: Double {
        switch style {
        case .primary: return 10
        case .secondary: return 6
        case .tertiary: return 4
        case .custom: return 6
        }
    }

    private var shadowOffset: Double {
        switch style {
        case .primary: return 5
        case .secondary: return 3
        case .tertiary: return 2
        case .custom: return 3
        }
    }
}

// MARK: - macOS 26 Glass Card Component

/// A card component that uses native glass effects on macOS 26
struct GlassCard<Content: View>: View {
    let content: Content
    let style: AdaptiveGlassMaterial.GlassStyle
    let padding: CGFloat

    init(
        style: AdaptiveGlassMaterial.GlassStyle = .primary,
        padding: CGFloat = DesignSystem.spacingMedium,
        @ViewBuilder content: () -> Content
    ) {
        self.style = style
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .modifier(AdaptiveGlassMaterial(style: style))
            .accessibilityElement(children: .contain)
    }
}

// MARK: - macOS 26 Glass Button Component

/// A button with native glass styling for macOS 26
struct GlassButton: View {
    let title: String
    let icon: String?
    let isProminent: Bool
    let action: () -> Void

    init(
        _ title: String,
        icon: String? = nil,
        isProminent: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.isProminent = isProminent
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: DesignSystem.spacingXSmall) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .medium))
                }
                Text(title)
                    .font(DesignSystem.Typography.buttonText)
            }
        }
        .buttonStyle(TahoeGlassButtonStyle(isProminent: isProminent))
        .accessibleControl(label: title, hint: isProminent ? "Primary action" : nil)
    }
}

// MARK: - macOS 26 Glass Toolbar Button

/// A toolbar-optimized glass button
struct GlassToolbarButton: View {
    let title: String
    let icon: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                Text(title)
                    .font(.system(size: 13, weight: .medium))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .tahoeGlassCard(cornerRadius: 6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color.primary.opacity(isHovered ? 0.2 : 0.1), lineWidth: 0.5)
            )
            .scaleEffect(isHovered ? 1.02 : 1.0)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(DesignSystem.quickFade) {
                isHovered = hovering
            }
        }
        .accessibleControl(label: title)
    }
}
