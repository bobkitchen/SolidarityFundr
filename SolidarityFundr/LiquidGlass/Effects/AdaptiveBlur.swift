//
//  AdaptiveBlur.swift
//  SolidarityFundr
//
//  Created on 7/20/25.
//  Adaptive blur system for Liquid Glass design
//

import SwiftUI
import Combine

// MARK: - Adaptive Blur View Modifier
struct AdaptiveBlurModifier: ViewModifier {
    @State private var blurRadius: Double
    @State private var isAnimating = false
    
    let minRadius: Double
    let maxRadius: Double
    let adaptToContent: Bool
    let animationDuration: Double
    
    init(
        baseRadius: Double = 8,
        minRadius: Double = 2,
        maxRadius: Double = 12,
        adaptToContent: Bool = true,
        animationDuration: Double = 0.3
    ) {
        self._blurRadius = State(initialValue: baseRadius)
        self.minRadius = minRadius
        self.maxRadius = maxRadius
        self.adaptToContent = adaptToContent
        self.animationDuration = animationDuration
    }
    
    func body(content: Content) -> some View {
        content
            .background(
                BlurredBackground(radius: blurRadius)
            )
            .onHover { hovering in
                withAnimation(.easeInOut(duration: animationDuration)) {
                    blurRadius = hovering ? maxRadius : minRadius
                }
            }
    }
}

// MARK: - Blurred Background Component
struct BlurredBackground: View {
    let radius: Double
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        Rectangle()
            .fill(.ultraThinMaterial)
            .blur(radius: radius)
            .overlay(
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color.white.opacity(0.1),
                        Color.clear
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
    }
}

// MARK: - Content-Aware Blur
struct ContentAwareBlur: ViewModifier {
    @State private var contentBrightness: Double = 0.5
    @State private var blurRadius: Double = 8
    @State private var colorSamples: [Color] = []
    
    let sampleInterval: TimeInterval = 0.1
    private let timer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()
    
    func body(content: Content) -> some View {
        content
            .background(
                GeometryReader { geometry in
                    ZStack {
                        // Base blur layer
                        Rectangle()
                            .fill(.ultraThinMaterial)
                            .blur(radius: adaptiveRadius)
                        
                        // Dynamic color overlay
                        if !colorSamples.isEmpty {
                            LinearGradient(
                                colors: colorSamples,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                            .opacity(0.05)
                        }
                    }
                }
            )
            .onReceive(timer) { _ in
                updateBlurParameters()
            }
    }
    
    private var adaptiveRadius: Double {
        // Adjust blur based on content brightness
        let brightnessMultiplier = 1.0 + (contentBrightness - 0.5) * 0.4
        return blurRadius * brightnessMultiplier
    }
    
    private func updateBlurParameters() {
        // Simulate content analysis
        // In a real implementation, this would sample the actual content
        withAnimation(.easeInOut(duration: 0.3)) {
            contentBrightness = Double.random(in: 0.3...0.7)
            blurRadius = Double.random(in: 6...10)
        }
    }
}

// MARK: - Directional Blur
struct DirectionalBlur: ViewModifier {
    let direction: BlurDirection
    let intensity: Double
    
    enum BlurDirection {
        case horizontal
        case vertical
        case radial
        case angular
    }
    
    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geometry in
                    switch direction {
                    case .horizontal:
                        HorizontalBlurLayer(intensity: intensity, size: geometry.size)
                    case .vertical:
                        VerticalBlurLayer(intensity: intensity, size: geometry.size)
                    case .radial:
                        RadialBlurLayer(intensity: intensity, size: geometry.size)
                    case .angular:
                        AngularBlurLayer(intensity: intensity, size: geometry.size)
                    }
                }
            )
    }
}

// MARK: - Blur Layer Components
struct HorizontalBlurLayer: View {
    let intensity: Double
    let size: CGSize
    
    var body: some View {
        LinearGradient(
            gradient: Gradient(stops: [
                .init(color: .clear, location: 0),
                .init(color: .white.opacity(0.1), location: 0.5),
                .init(color: .clear, location: 1)
            ]),
            startPoint: .leading,
            endPoint: .trailing
        )
        .blur(radius: intensity, opaque: false)
    }
}

struct VerticalBlurLayer: View {
    let intensity: Double
    let size: CGSize
    
    var body: some View {
        LinearGradient(
            gradient: Gradient(stops: [
                .init(color: .clear, location: 0),
                .init(color: .white.opacity(0.1), location: 0.5),
                .init(color: .clear, location: 1)
            ]),
            startPoint: .top,
            endPoint: .bottom
        )
        .blur(radius: intensity, opaque: false)
    }
}

struct RadialBlurLayer: View {
    let intensity: Double
    let size: CGSize
    
    var body: some View {
        RadialGradient(
            gradient: Gradient(colors: [
                .white.opacity(0.2),
                .clear
            ]),
            center: .center,
            startRadius: 0,
            endRadius: min(size.width, size.height) / 2
        )
        .blur(radius: intensity, opaque: false)
    }
}

struct AngularBlurLayer: View {
    let intensity: Double
    let size: CGSize
    @State private var rotation: Double = 0
    
    var body: some View {
        ZStack {
            ForEach(0..<8) { index in
                Rectangle()
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                .white.opacity(0.05),
                                .clear
                            ]),
                            startPoint: .center,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: size.width * 1.5, height: 2)
                    .blur(radius: intensity)
                    .rotationEffect(.degrees(Double(index) * 45 + rotation))
            }
        }
        .onAppear {
            withAnimation(.linear(duration: 30).repeatForever(autoreverses: false)) {
                rotation = 360
            }
        }
    }
}

// MARK: - View Extensions
extension View {
    func adaptiveBlur(
        baseRadius: Double = 8,
        minRadius: Double = 2,
        maxRadius: Double = 12
    ) -> some View {
        self.modifier(
            AdaptiveBlurModifier(
                baseRadius: baseRadius,
                minRadius: minRadius,
                maxRadius: maxRadius
            )
        )
    }
    
    func contentAwareBlur() -> some View {
        self.modifier(ContentAwareBlur())
    }
    
    func directionalBlur(
        _ direction: DirectionalBlur.BlurDirection,
        intensity: Double = 8
    ) -> some View {
        self.modifier(DirectionalBlur(direction: direction, intensity: intensity))
    }
}