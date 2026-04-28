//
//  MemberAvatar.swift
//  SolidarityFundr
//
//  Shared avatar primitive. If the member has uploaded a photo, render
//  it (clipped to a circle); otherwise fall back to a deterministic
//  per-member-coloured disc with a white person silhouette overlaid.
//
//  Used wherever a member's identity is shown at meaningful size:
//  the member detail header, the members list. The dashboard's
//  transaction-row "avatarDot" stays a pure colour at ~10pt because
//  photos are illegible at that scale.
//

import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct MemberAvatar: View {
    let member: Member
    let size: CGFloat

    init(member: Member, size: CGFloat = 56) {
        self.member = member
        self.size = size
    }

    var body: some View {
        Group {
            if let data = member.photoData, let image = Self.image(from: data) {
                image
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Circle()
                        .fill(BrandColor.avatarTint(for: member.name))
                    Image(systemName: "person.fill")
                        .font(.system(size: size * 0.45, weight: .medium))
                        .foregroundStyle(.white)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }

    private static func image(from data: Data) -> Image? {
        #if os(macOS)
        guard let ns = NSImage(data: data) else { return nil }
        return Image(nsImage: ns)
        #else
        guard let ui = UIImage(data: data) else { return nil }
        return Image(uiImage: ui)
        #endif
    }
}
