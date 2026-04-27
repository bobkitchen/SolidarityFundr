//
//  LiquidGlassEffects.swift
//  SolidarityFundr
//
//  Thin compatibility layer. The previous custom glass simulators
//  (PerformantGlassLayer, primaryGlass/secondaryGlass/tertiaryGlass,
//  liquidGlassSidebar, LiquidGlassButtonStyle, OptimizedHoverOverlay,
//  AdaptiveShadow, InteractiveGlassControl, etc.) were actively suppressing
//  the system's automatic Liquid Glass rendering on macOS 26.
//
//  We now route every helper through stock SwiftUI containers so the system
//  can apply real Liquid Glass on macOS 26 / iOS 26 (and a sensible Material
//  fallback on earlier OS versions).
//

import SwiftUI

extension View {
    /// Card-style background. On macOS 26 the system renders Liquid Glass on
    /// `.regularMaterial`-backed surfaces inside navigation containers; on
    /// older OS this is a frosted Material card.
    @ViewBuilder
    func primaryGlass(cornerRadius: CGFloat = DesignSystem.cornerRadiusLarge) -> some View {
        materialCard(cornerRadius: cornerRadius, material: .regularMaterial)
    }

    @ViewBuilder
    func secondaryGlass(cornerRadius: CGFloat = DesignSystem.cornerRadiusMedium) -> some View {
        materialCard(cornerRadius: cornerRadius, material: .ultraThinMaterial)
    }

    @ViewBuilder
    func tertiaryGlass(cornerRadius: CGFloat = DesignSystem.cornerRadiusSmall) -> some View {
        materialCard(cornerRadius: cornerRadius, material: .thinMaterial)
    }

    /// Backwards-compatible alias for the now-deleted `performantGlass` /
    /// `nativeGlass` / `interactiveGlass` modifiers. Stock Material card.
    @ViewBuilder
    func performantGlass(
        material: Material = .ultraThinMaterial,
        cornerRadius: CGFloat = DesignSystem.cornerRadiusMedium,
        strokeWidth: CGFloat = 0.5,
        strokeOpacity: Double = 0.1
    ) -> some View {
        materialCard(cornerRadius: cornerRadius, material: material)
    }

    @ViewBuilder
    func nativeGlass(cornerRadius: CGFloat = DesignSystem.cornerRadiusMedium) -> some View {
        materialCard(cornerRadius: cornerRadius, material: .ultraThinMaterial)
    }

    @ViewBuilder
    func interactiveGlass(cornerRadius: CGFloat = DesignSystem.cornerRadiusSmall) -> some View {
        materialCard(cornerRadius: cornerRadius, material: .thinMaterial)
    }

    @ViewBuilder
    private func materialCard(cornerRadius: CGFloat, material: Material) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        self.background(material, in: shape)
            .clipShape(shape)
    }

    /// No-op replacement for the previous hover overlay modifier.
    func hoverOverlay(isHovered: Bool, cornerRadius: CGFloat = 12, intensity: Double = 0.1) -> some View {
        self
    }

    /// No-op replacement for the previous shadow modifier — system styles
    /// (List rows, GroupBox, Liquid Glass) provide elevation cues automatically.
    func adaptiveShadow(isHovered: Bool, isSelected: Bool = false, baseRadius: CGFloat = 8, baseOpacity: Double = 0.1) -> some View {
        self
    }

    /// No-op replacement for the previous interactive-glass-control modifier.
    func interactiveGlassControl(cornerRadius: CGFloat = 8) -> some View {
        self
    }
}
