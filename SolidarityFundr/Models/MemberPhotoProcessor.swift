//
//  MemberPhotoProcessor.swift
//  SolidarityFundr
//
//  Normalises member-photo uploads into a small, square, CloudKit-safe
//  JPEG. Avatars render at <= 64pt; storing 4000×3000 raw camera output
//  would bloat both the SQLite store and the CKAsset uploaded to iCloud
//  for no visible quality benefit.
//
//  Pipeline:
//    1. Centre-square-crop the source so the round avatar mask doesn't
//       cut faces off-centre when the source is portrait or landscape.
//    2. Resize to a max edge of 512 px (covers @3x phone displays).
//    3. JPEG-compress at quality 0.8.
//

import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

#if os(macOS)
import AppKit
#else
import UIKit
#endif

enum MemberPhotoProcessor {

    static let maxEdge: CGFloat = 512
    static let jpegQuality: CGFloat = 0.8

    /// Returns square-cropped, resized, JPEG-encoded bytes suitable for
    /// storage on `Member.photoData`. Returns nil if the input can't be
    /// decoded as an image.
    static func process(_ data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return nil
        }

        let cropped = squareCrop(cgImage)
        let resized = resize(cropped, maxEdge: maxEdge)
        return jpegEncode(resized)
    }

    // MARK: - Steps

    private static func squareCrop(_ image: CGImage) -> CGImage {
        let w = CGFloat(image.width)
        let h = CGFloat(image.height)
        guard w != h else { return image }
        let edge = min(w, h)
        let originX = (w - edge) / 2
        let originY = (h - edge) / 2
        let rect = CGRect(x: originX, y: originY, width: edge, height: edge).integral
        return image.cropping(to: rect) ?? image
    }

    private static func resize(_ image: CGImage, maxEdge: CGFloat) -> CGImage {
        let w = CGFloat(image.width)
        let h = CGFloat(image.height)
        let longest = max(w, h)
        guard longest > maxEdge else { return image }
        let scale = maxEdge / longest
        let newW = Int((w * scale).rounded())
        let newH = Int((h * scale).rounded())
        let colorSpace = image.colorSpace ?? CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: newW,
            height: newH,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return image }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: newW, height: newH))
        return context.makeImage() ?? image
    }

    private static func jpegEncode(_ image: CGImage) -> Data? {
        let mutable = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            mutable, UTType.jpeg.identifier as CFString, 1, nil
        ) else { return nil }
        let options: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: jpegQuality
        ]
        CGImageDestinationAddImage(dest, image, options as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return mutable as Data
    }
}
