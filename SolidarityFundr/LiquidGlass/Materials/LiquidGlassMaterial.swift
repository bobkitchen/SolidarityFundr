//
//  LiquidGlassMaterial.swift
//  SolidarityFundr
//
//  Created on 7/20/25.
//  Liquid Glass Design System for macOS Tahoe
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
enum MaterialThickness: Double {
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
}

// MARK: - Primary Glass Material
struct PrimaryGlassMaterial: ViewModifier, LiquidGlassMaterial {
    let transparency: Double = 0.85
    let blurRadius: Double = 12
    let tintColor: Color? = nil
    let specularIntensity: Double = 0.8
    let thickness: MaterialThickness = .regular
    
    @Environment(\.colorScheme) var colorScheme
    
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(glassTint)
                            .opacity(0.05)
                    )
                    .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
            )
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
    
    @Environment(\.colorScheme) var colorScheme
    
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.regularMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(glassTint)
                            .opacity(0.08)
                    )
                    .shadow(color: .black.opacity(0.08), radius: 6, x: 0, y: 3)
            )
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
    
    @Environment(\.colorScheme) var colorScheme
    
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(.thinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(glassTint)
                            .opacity(0.12)
                    )
                    .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
            )
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
    func primaryGlass() -> some View {
        self.modifier(PrimaryGlassMaterial())
    }
    
    func secondaryGlass() -> some View {
        self.modifier(SecondaryGlassMaterial())
    }
    
    func tertiaryGlass() -> some View {
        self.modifier(TertiaryGlassMaterial())
    }
}

// MARK: - Adaptive Glass Material
struct AdaptiveGlassMaterial: ViewModifier {
    let style: GlassStyle
    @State private var adaptiveBlurRadius: Double = 8
    @State private var adaptiveTint: Color = .clear
    
    enum GlassStyle {
        case primary, secondary, tertiary, custom(transparency: Double, blur: Double)
    }
    
    func body(content: Content) -> some View {
        content
            .background(
                GeometryReader { geometry in
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(material)
                        .overlay(
                            RoundedRectangle(cornerRadius: cornerRadius)
                                .fill(adaptiveTint)
                                .opacity(tintOpacity)
                        )
                        .shadow(color: shadowColor, radius: shadowRadius, x: 0, y: shadowOffset)
                }
            )
            .onAppear {
                startAdaptiveAnimation()
            }
    }
    
    private var cornerRadius: Double {
        switch style {
        case .primary: return 20
        case .secondary: return 16
        case .tertiary: return 12
        case .custom: return 16
        }
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
    
    private func startAdaptiveAnimation() {
        withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
            adaptiveBlurRadius = adaptiveBlurRadius * 1.2
        }
    }
}

// MARK: - Glass Card Component
struct GlassCard<Content: View>: View {
    let content: Content
    let style: AdaptiveGlassMaterial.GlassStyle
    
    init(style: AdaptiveGlassMaterial.GlassStyle = .primary, @ViewBuilder content: () -> Content) {
        self.style = style
        self.content = content()
    }
    
    var body: some View {
        content
            .modifier(AdaptiveGlassMaterial(style: style))
    }
}