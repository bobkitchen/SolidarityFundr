//
//  Theme.swift
//  SolidarityFundr
//
//  Parachichi brand palette and section identity.
//
//  The accent color (avocado green) is set in Assets.xcassets/AccentColor and
//  resolves automatically through Color.accentColor / .tint. The colors below
//  are the supporting brand inks used for per-section identity, status, and
//  member avatar deterministic tinting.
//

import SwiftUI
import CryptoKit

enum BrandColor {
    /// Primary avocado green — same as AccentColor.colorset.
    static let avocado = Color(red: 0.353, green: 0.451, blue: 0.251)
    /// Olive — Members section.
    static let olive = Color(red: 0.494, green: 0.541, blue: 0.298)
    /// Honey — Loans section, also used for amber states.
    static let honey = Color(red: 0.804, green: 0.604, blue: 0.255)
    /// Terracotta — Payments section.
    static let terracotta = Color(red: 0.745, green: 0.388, blue: 0.275)
    /// Indigo ink — Reports section.
    static let indigoInk = Color(red: 0.243, green: 0.314, blue: 0.498)
    /// Rust — overdue / errors.
    static let rust = Color(red: 0.671, green: 0.231, blue: 0.235)
    /// Cream — paper-warm light surface (used sparingly).
    static let cream = Color(red: 0.973, green: 0.953, blue: 0.922)

    /// Member avatar palette. Deterministic mapping from a member name avoids
    /// the everyone-looks-the-same problem without uploading photos.
    static let avatarPalette: [Color] = [
        avocado, olive, honey, terracotta, indigoInk,
        Color(red: 0.467, green: 0.318, blue: 0.475), // plum
        Color(red: 0.314, green: 0.518, blue: 0.494), // teal
        Color(red: 0.580, green: 0.267, blue: 0.298)  // mulberry
    ]

    /// Hash a string into a deterministic palette index. Same input always
    /// resolves to the same color across launches/devices.
    static func avatarTint(for key: String?) -> Color {
        guard let key, !key.isEmpty else { return avocado }
        let bytes = Data(key.utf8)
        let digest = SHA256.hash(data: bytes)
        let firstByte = digest.compactMap { $0 }.first ?? 0
        let index = Int(firstByte) % avatarPalette.count
        return avatarPalette[index]
    }
}

/// Per-section identity. Each `DashboardSection` gets a tint so Members reads
/// olive, Loans reads honey, etc. Pages call `.tint(section.tint)` so all the
/// system-derived accents (selection highlights, link colors, ProgressView,
/// .borderedProminent buttons) follow.
extension DashboardSection {
    var tint: Color {
        switch self {
        case .overview: return BrandColor.avocado
        case .members:  return BrandColor.olive
        case .loans:    return BrandColor.honey
        case .payments: return BrandColor.terracotta
        case .reports:  return BrandColor.indigoInk
        }
    }
}

// MARK: - Editorial typography helpers

extension Font {
    /// Editorial display: rounded-serif weight for hero numerics. Uses NY
    /// (system serif) so it ships with the OS — no custom font registration.
    static func heroSerif(_ size: CGFloat = 44) -> Font {
        .system(size: size, weight: .semibold, design: .serif)
    }

    /// Hero numerics with monospaced digits. Use for fund balance and other
    /// "this number matters" displays.
    static func heroNumeric(_ size: CGFloat = 44) -> Font {
        .system(size: size, weight: .semibold, design: .rounded).monospacedDigit()
    }
}

// MARK: - KSH currency pill

/// Small tinted "KSH" capsule before a currency value. Used in detail-view
/// headers (loan amount, member contribution total) where the currency
/// deserves emphasis. Kept rare — overuse would be noisy.
struct CurrencyPill: View {
    let amount: Double
    var tint: Color = BrandColor.avocado
    var size: CGFloat = 28

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("KSH")
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(tint.opacity(0.15), in: Capsule())
                .foregroundStyle(tint)

            Text(amount, format: .number)
                .font(.system(size: size, weight: .semibold, design: .rounded))
                .monospacedDigit()
        }
    }
}

// MARK: - Loan progress gradient

extension LinearGradient {
    /// Maps a loan completion percentage (0–100) to a green→amber→red
    /// gradient. Communicates payoff progress at a glance — green is
    /// healthy, honey is mid-cycle, rust is overdue territory.
    static func loanProgress(percentage: Double) -> LinearGradient {
        LinearGradient(
            colors: [BrandColor.avocado, BrandColor.honey, BrandColor.rust],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}
