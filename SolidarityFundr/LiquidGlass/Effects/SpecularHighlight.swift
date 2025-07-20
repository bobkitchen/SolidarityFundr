//
//  SpecularHighlight.swift
//  SolidarityFundr
//
//  Created on 7/20/25.
//  Specular highlighting system for Liquid Glass design
//

import SwiftUI

// MARK: - Specular Highlight Modifier
struct SpecularHighlightModifier: ViewModifier {
    @State private var highlightPosition: CGPoint = .zero
    @State private var isHighlighted: Bool = false
    
    let intensity: Double
    let size: CGFloat
    let tracksMouse: Bool
    
    init(intensity: Double = 0.8, size: CGFloat = 100, tracksMouse: Bool = true) {
        self.intensity = intensity
        self.size = size
        self.tracksMouse = tracksMouse
    }
    
    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geometry in
                    if isHighlighted {
                        SpecularLayer(
                            position: highlightPosition,
                            intensity: intensity,
                            size: size,
                            containerSize: geometry.size
                        )
                    }
                }
            )
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.2)) {
                    isHighlighted = hovering
                }
            }
            .onContinuousHover { phase in
                if tracksMouse {
                    switch phase {
                    case .active(let location):
                        highlightPosition = location
                    case .ended:
                        isHighlighted = false
                    }
                }
            }
    }
}

// MARK: - Specular Layer
struct SpecularLayer: View {
    let position: CGPoint
    let intensity: Double
    let size: CGFloat
    let containerSize: CGSize
    
    var body: some View {
        Canvas { context, size in
            // Primary highlight
            let primaryGradient = Gradient(colors: [
                .white.opacity(intensity),
                .white.opacity(intensity * 0.5),
                .clear
            ])
            
            let _ = RadialGradient(
                gradient: primaryGradient,
                center: UnitPoint(
                    x: position.x / containerSize.width,
                    y: position.y / containerSize.height
                ),
                startRadius: 0,
                endRadius: self.size
            )
            
            context.fill(
                Path(ellipseIn: CGRect(
                    x: position.x - self.size,
                    y: position.y - self.size,
                    width: self.size * 2,
                    height: self.size * 2
                )),
                with: .radialGradient(
                    primaryGradient,
                    center: position,
                    startRadius: 0,
                    endRadius: self.size
                )
            )
            
            // Secondary rim light
            let rimGradient = Gradient(colors: [
                .clear,
                .white.opacity(intensity * 0.3),
                .clear
            ])
            
            context.fill(
                Path(ellipseIn: CGRect(
                    x: position.x - self.size * 1.5,
                    y: position.y - self.size * 1.5,
                    width: self.size * 3,
                    height: self.size * 3
                )),
                with: .radialGradient(
                    rimGradient,
                    center: position,
                    startRadius: self.size * 0.8,
                    endRadius: self.size * 1.5
                )
            )
        }
        .allowsHitTesting(false)
        .blendMode(.screen)
    }
}

// MARK: - Animated Specular Highlight
struct AnimatedSpecularHighlight: View {
    @State private var phase: CGFloat = 0
    let intensity: Double
    let speed: Double
    
    init(intensity: Double = 0.6, speed: Double = 2.0) {
        self.intensity = intensity
        self.speed = speed
    }
    
    var body: some View {
        GeometryReader { geometry in
            LinearGradient(
                gradient: Gradient(stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .white.opacity(intensity), location: 0.45 + phase),
                    .init(color: .white.opacity(intensity * 0.3), location: 0.5 + phase),
                    .init(color: .white.opacity(intensity), location: 0.55 + phase),
                    .init(color: .clear, location: 1)
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .blendMode(.screen)
            .allowsHitTesting(false)
            .mask(
                RoundedRectangle(cornerRadius: 20)
            )
        }
        .onAppear {
            withAnimation(
                .linear(duration: speed)
                .repeatForever(autoreverses: false)
            ) {
                phase = 1.0
            }
        }
    }
}

// MARK: - Light Simulation
struct LightSimulation: ViewModifier {
    @State private var lightAngle: Double = 45
    @State private var lightIntensity: Double = 0.7
    @Environment(\.colorScheme) var colorScheme
    
    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geometry in
                    ZStack {
                        // Top light
                        LinearGradient(
                            gradient: Gradient(colors: [
                                lightColor.opacity(lightIntensity),
                                .clear
                            ]),
                            startPoint: .top,
                            endPoint: .center
                        )
                        .blendMode(.screen)
                        
                        // Side light based on angle
                        LinearGradient(
                            gradient: Gradient(colors: [
                                lightColor.opacity(lightIntensity * 0.5),
                                .clear
                            ]),
                            startPoint: startPoint,
                            endPoint: .center
                        )
                        .blendMode(.screen)
                    }
                }
                .allowsHitTesting(false)
            )
    }
    
    private var lightColor: Color {
        colorScheme == .dark ? .white : .white
    }
    
    private var startPoint: UnitPoint {
        let radians = lightAngle * .pi / 180
        let x = 0.5 + cos(radians) * 0.5
        let y = 0.5 - sin(radians) * 0.5
        return UnitPoint(x: x, y: y)
    }
}

// MARK: - Glass Reflection
struct GlassReflection: View {
    let intensity: Double
    
    var body: some View {
        GeometryReader { geometry in
            LinearGradient(
                gradient: Gradient(stops: [
                    .init(color: .white.opacity(intensity), location: 0),
                    .init(color: .white.opacity(intensity * 0.5), location: 0.1),
                    .init(color: .clear, location: 0.5)
                ]),
                startPoint: .top,
                endPoint: .center
            )
            .blendMode(.screen)
            .mask(
                RoundedRectangle(cornerRadius: 20)
            )
        }
    }
}

// MARK: - View Extensions
extension View {
    func specularHighlight(
        intensity: Double = 0.8,
        size: CGFloat = 100,
        tracksMouse: Bool = true
    ) -> some View {
        self.modifier(
            SpecularHighlightModifier(
                intensity: intensity,
                size: size,
                tracksMouse: tracksMouse
            )
        )
    }
    
    func animatedSpecular(
        intensity: Double = 0.6,
        speed: Double = 2.0
    ) -> some View {
        self.overlay(
            AnimatedSpecularHighlight(
                intensity: intensity,
                speed: speed
            )
        )
    }
    
    func lightSimulation() -> some View {
        self.modifier(LightSimulation())
    }
    
    func glassReflection(intensity: Double = 0.3) -> some View {
        self.overlay(
            GlassReflection(intensity: intensity)
        )
    }
}