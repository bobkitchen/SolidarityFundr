//
//  LiquidGlassEffects.swift
//  SolidarityFundr
//
//  Created on 7/20/25.
//  Liquid Glass Effects - macOS 26 Tahoe HIG Compliant
//

import SwiftUI

// MARK: - Optimized Hover Overlay

struct OptimizedHoverOverlay: ViewModifier {
    let isHovered: Bool
    let cornerRadius: CGFloat
    let intensity: Double

    init(isHovered: Bool, cornerRadius: CGFloat, intensity: Double = 0.1) {
        self.isHovered = isHovered
        self.cornerRadius = cornerRadius
        self.intensity = intensity
    }

    func body(content: Content) -> some View {
        content
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(isHovered ? intensity : 0),
                                Color.clear
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .allowsHitTesting(false)
                    .animation(.easeOut(duration: 0.15), value: isHovered)
            )
    }
}

// MARK: - Performance-Optimized Glass Layer (Legacy Fallback)

/// Legacy glass layer for pre-macOS 26 systems
/// On macOS 26+, prefer using native .glassEffect() modifier
struct PerformantGlassLayer: View {
    let material: Material
    let cornerRadius: CGFloat
    let strokeWidth: CGFloat
    let strokeOpacity: Double

    init(
        material: Material = .ultraThinMaterial,
        cornerRadius: CGFloat = DesignSystem.cornerRadiusMedium,
        strokeWidth: CGFloat = 0.5,
        strokeOpacity: Double = 0.1
    ) {
        self.material = material
        self.cornerRadius = cornerRadius
        self.strokeWidth = strokeWidth
        self.strokeOpacity = strokeOpacity
    }

    var body: some View {
        ZStack {
            // Base material layer
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(material)

            // Single stroke overlay for performance
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(strokeOpacity),
                            Color.white.opacity(strokeOpacity * 0.5)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: strokeWidth
                )
        }
    }
}

// MARK: - macOS 26 Native Glass Layer

/// Native glass layer using material backgrounds
struct NativeGlassLayer: View {
    let cornerRadius: CGFloat

    init(cornerRadius: CGFloat = DesignSystem.cornerRadiusMedium) {
        self.cornerRadius = cornerRadius
    }

    var body: some View {
        PerformantGlassLayer(cornerRadius: cornerRadius)
    }
}

// MARK: - Adaptive Shadow System

struct AdaptiveShadow: ViewModifier {
    let isHovered: Bool
    let isSelected: Bool
    let baseRadius: CGFloat
    let baseOpacity: Double

    init(
        isHovered: Bool,
        isSelected: Bool = false,
        baseRadius: CGFloat = 8,
        baseOpacity: Double = 0.1
    ) {
        self.isHovered = isHovered
        self.isSelected = isSelected
        self.baseRadius = baseRadius
        self.baseOpacity = baseOpacity
    }

    private var shadowRadius: CGFloat {
        if isSelected { return baseRadius * 1.5 }
        if isHovered { return baseRadius * 1.25 }
        return baseRadius
    }

    private var shadowOpacity: Double {
        if isSelected { return baseOpacity * 1.5 }
        if isHovered { return baseOpacity * 1.25 }
        return baseOpacity
    }

    private var shadowY: CGFloat {
        if isSelected { return baseRadius * 0.75 }
        if isHovered { return baseRadius * 0.625 }
        return baseRadius * 0.5
    }

    func body(content: Content) -> some View {
        content
            .shadow(
                color: Color.black.opacity(shadowOpacity),
                radius: shadowRadius,
                x: 0,
                y: shadowY
            )
    }
}

// MARK: - Liquid Glass Button Style (Updated for macOS 26)

struct LiquidGlassButtonStyle: ButtonStyle {
    let cornerRadius: CGFloat
    let material: Material

    init(
        cornerRadius: CGFloat = DesignSystem.cornerRadiusSmall,
        material: Material = .ultraThinMaterial
    ) {
        self.cornerRadius = cornerRadius
        self.material = material
    }

    func makeBody(configuration: Configuration) -> some View {
        ButtonView(configuration: configuration, cornerRadius: cornerRadius, material: material)
    }

    struct ButtonView: View {
        let configuration: ButtonStyleConfiguration
        let cornerRadius: CGFloat
        let material: Material
        @State private var isHovered = false

        var body: some View {
            configuration.label
                .background(
                    PerformantGlassLayer(
                        material: material,
                        cornerRadius: cornerRadius,
                        strokeOpacity: isHovered ? 0.2 : 0.1
                    )
                )
                .scaleEffect(configuration.isPressed ? 0.97 : (isHovered ? 1.02 : 1.0))
                .modifier(
                    AdaptiveShadow(
                        isHovered: isHovered,
                        isSelected: configuration.isPressed,
                        baseRadius: 4,
                        baseOpacity: 0.08
                    )
                )
                .modifier(
                    OptimizedHoverOverlay(
                        isHovered: isHovered,
                        cornerRadius: cornerRadius
                    )
                )
                .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isHovered)
                .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
                .onHover { hovering in
                    isHovered = hovering
                }
        }
    }
}

// MARK: - View Extensions

extension View {
    /// Apply optimized hover overlay
    func hoverOverlay(
        isHovered: Bool,
        cornerRadius: CGFloat = DesignSystem.cornerRadiusMedium,
        intensity: Double = 0.1
    ) -> some View {
        modifier(OptimizedHoverOverlay(
            isHovered: isHovered,
            cornerRadius: cornerRadius,
            intensity: intensity
        ))
    }

    /// Apply adaptive shadow system
    func adaptiveShadow(
        isHovered: Bool,
        isSelected: Bool = false,
        baseRadius: CGFloat = 8,
        baseOpacity: Double = 0.1
    ) -> some View {
        modifier(AdaptiveShadow(
            isHovered: isHovered,
            isSelected: isSelected,
            baseRadius: baseRadius,
            baseOpacity: baseOpacity
        ))
    }

    /// Apply a glass background. On macOS 26+/iOS 26+ uses native Liquid Glass
    /// via `glassEffect`; on earlier OS versions falls back to a Material-based
    /// layer that approximates the look.
    @ViewBuilder
    func performantGlass(
        material: Material = .ultraThinMaterial,
        cornerRadius: CGFloat = DesignSystem.cornerRadiusMedium,
        strokeWidth: CGFloat = 0.5,
        strokeOpacity: Double = 0.1
    ) -> some View {
        if #available(macOS 26.0, iOS 26.0, *) {
            self.glassEffect(in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        } else {
            self.background(
                PerformantGlassLayer(
                    material: material,
                    cornerRadius: cornerRadius,
                    strokeWidth: strokeWidth,
                    strokeOpacity: strokeOpacity
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
    }

    /// Apply a native glass effect (alias of `performantGlass` with defaults).
    @ViewBuilder
    func nativeGlass(cornerRadius: CGFloat = DesignSystem.cornerRadiusMedium) -> some View {
        self.performantGlass(material: .ultraThinMaterial, cornerRadius: cornerRadius)
    }

    /// Apply interactive glass for buttons and controls. On macOS 26+ uses
    /// `.glassEffect(.regular.interactive())` which provides built-in scale,
    /// shimmer, and touch-point illumination.
    @ViewBuilder
    func interactiveGlass(cornerRadius: CGFloat = DesignSystem.cornerRadiusSmall) -> some View {
        if #available(macOS 26.0, iOS 26.0, *) {
            self.glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        } else {
            self.background(
                PerformantGlassLayer(
                    material: .thinMaterial,
                    cornerRadius: cornerRadius
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
    }
}

// MARK: - Tiered Glass Modifiers
//
// Replacements for the legacy LiquidGlassMaterial.swift `primaryGlass`/
// `secondaryGlass`/`tertiaryGlass` modifiers. These now route through the
// native gate in `performantGlass` so on macOS 26+ they render as real
// Liquid Glass, falling back to `Material` on earlier OS versions.
// No hardcoded shadows — the system handles edge effects.

extension View {
    @ViewBuilder
    func primaryGlass(cornerRadius: CGFloat = DesignSystem.cornerRadiusLarge) -> some View {
        self.performantGlass(material: .ultraThinMaterial, cornerRadius: cornerRadius)
    }

    @ViewBuilder
    func secondaryGlass(cornerRadius: CGFloat = DesignSystem.cornerRadiusMedium) -> some View {
        self.performantGlass(material: .regularMaterial, cornerRadius: cornerRadius)
    }

    @ViewBuilder
    func tertiaryGlass(cornerRadius: CGFloat = DesignSystem.cornerRadiusSmall) -> some View {
        self.performantGlass(material: .thinMaterial, cornerRadius: cornerRadius)
    }
}

// MARK: - Liquid Glass Sidebar (macOS 26 Updated)

extension View {
    /// Apply liquid glass sidebar styling. On macOS 26+/iOS 26+ uses the native
    /// `glassEffect` so the sidebar actually renders as Liquid Glass (refraction,
    /// adaptive contrast). Falls back to `.regularMaterial` on older OS.
    @ViewBuilder
    func liquidGlassSidebar() -> some View {
        let shape = RoundedRectangle(cornerRadius: DesignSystem.cornerRadiusLarge, style: .continuous)
        if #available(macOS 26.0, iOS 26.0, *) {
            self.glassEffect(.regular, in: shape)
        } else {
            self.background(shape.fill(.regularMaterial))
                .clipShape(shape)
        }
    }
}

// MARK: - Glass Effect Container Wrapper

extension View {
    /// Wrap content in a GlassEffectContainer on macOS 26+
    /// Required when multiple glass elements need to sample each other correctly
    @ViewBuilder
    func glassContainer() -> some View {
        if #available(macOS 26.0, iOS 26.0, *) {
            GlassEffectContainer {
                self
            }
        } else {
            self
        }
    }
}

// MARK: - Interactive Glass Control Modifier

struct InteractiveGlassControl: ViewModifier {
    @State private var isHovered = false
    @State private var isPressed = false
    let cornerRadius: CGFloat

    init(cornerRadius: CGFloat = DesignSystem.cornerRadiusSmall) {
        self.cornerRadius = cornerRadius
    }

    func body(content: Content) -> some View {
        content
            .interactiveGlass(cornerRadius: cornerRadius)
            .scaleEffect(isPressed ? 0.97 : (isHovered ? 1.02 : 1.0))
            .animation(DesignSystem.interactiveSpring, value: isHovered)
            .animation(.easeOut(duration: 0.1), value: isPressed)
            .onHover { hovering in
                isHovered = hovering
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in isPressed = true }
                    .onEnded { _ in isPressed = false }
            )
    }
}

extension View {
    /// Make a view an interactive glass control with hover and press effects
    func interactiveGlassControl(cornerRadius: CGFloat = DesignSystem.cornerRadiusSmall) -> some View {
        modifier(InteractiveGlassControl(cornerRadius: cornerRadius))
    }
}

// MARK: - Status Badge with Glass Effect

struct GlassStatusBadge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(DesignSystem.Typography.badge)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundColor(color)
            .tertiaryGlass(cornerRadius: DesignSystem.cornerRadiusXSmall)
            .accessibilityLabel("Status: \(text)")
    }
}

// MARK: - Glass Metric Card

struct GlassMetricCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.spacingXSmall) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                    .font(.title3)
                Spacer()
            }

            Text(value)
                .font(DesignSystem.Typography.cardTitle)
                .fontWeight(.semibold)

            Text(title)
                .font(DesignSystem.Typography.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DesignSystem.spacingMedium)
        .secondaryGlass()
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .animation(DesignSystem.gentleSpring, value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
        .accessibleCard(label: title, value: value)
    }
}
