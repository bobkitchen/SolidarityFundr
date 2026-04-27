//
//  LiquidGlassExtensions.swift
//  SolidarityFundr
//
//  Created on 7/21/25.
//  Legacy extensions for pre-macOS 26 compatibility
//  Note: On macOS 26+, native glassEffect() is used via #available checks in other files
//

import SwiftUI

#if os(macOS)
// Extension for glass material fallback on older systems
extension ShapeStyle where Self == Material {
    /// Glass material - uses regularMaterial as a fallback representation
    static var glass: Material { .regularMaterial }
}

// MARK: - Legacy Glass Styles (for reference in non-macOS 26 code paths)

enum LegacyGlassStyle {
    case regular
    case thick
    case thin

    var material: Material {
        switch self {
        case .regular: return .regularMaterial
        case .thick: return .thickMaterial
        case .thin: return .thinMaterial
        }
    }
}
#endif