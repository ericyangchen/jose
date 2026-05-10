#!/usr/bin/env swift
// Generates a placeholder José app icon at 1024×1024 PNG and derives all
// required @1x/@2x sizes for AppIcon.appiconset.
//
// Usage:
//     swift Scripts/generate_icon.swift
//
// Output:
//     Resources/Assets.xcassets/AppIcon.appiconset/{Contents.json,*.png}
//
// This is the v1 placeholder (Siri-gradient square + glass waveform puck).
// Replace with a designer-quality version when one exists.

import AppKit
import Foundation

// MARK: - Sizes required by macOS app icon spec

struct IconSize {
    let size: CGFloat
    let scale: Int
    let filename: String
    var pixelSize: Int { Int(size) * scale }
}

let sizes: [IconSize] = [
    IconSize(size: 16,   scale: 1, filename: "icon_16x16.png"),
    IconSize(size: 16,   scale: 2, filename: "icon_16x16@2x.png"),
    IconSize(size: 32,   scale: 1, filename: "icon_32x32.png"),
    IconSize(size: 32,   scale: 2, filename: "icon_32x32@2x.png"),
    IconSize(size: 128,  scale: 1, filename: "icon_128x128.png"),
    IconSize(size: 128,  scale: 2, filename: "icon_128x128@2x.png"),
    IconSize(size: 256,  scale: 1, filename: "icon_256x256.png"),
    IconSize(size: 256,  scale: 2, filename: "icon_256x256@2x.png"),
    IconSize(size: 512,  scale: 1, filename: "icon_512x512.png"),
    IconSize(size: 512,  scale: 2, filename: "icon_512x512@2x.png")
]

// MARK: - Drawing

func drawIcon(into context: CGContext, pixelSize: Int) {
    let size = CGFloat(pixelSize)
    let cornerRadius: CGFloat = size * 0.22

    // Rounded square clipping path (Big Sur+ icon convention)
    let bgPath = CGPath(
        roundedRect: CGRect(x: 0, y: 0, width: size, height: size),
        cornerWidth: cornerRadius,
        cornerHeight: cornerRadius,
        transform: nil
    )
    context.saveGState()
    context.addPath(bgPath)
    context.clip()

    // Siri gradient (45°, top-left → bottom-right)
    let pink   = CGColor(red: 0.949, green: 0.659, blue: 0.769, alpha: 1)
    let purple = CGColor(red: 0.710, green: 0.659, blue: 0.910, alpha: 1)
    let blue   = CGColor(red: 0.561, green: 0.737, blue: 0.910, alpha: 1)
    let cyan   = CGColor(red: 0.584, green: 0.863, blue: 0.875, alpha: 1)

    let gradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [pink, purple, blue, cyan] as CFArray,
        locations: [0, 0.4, 0.7, 1]
    )!
    context.drawLinearGradient(
        gradient,
        start: CGPoint(x: 0, y: size),
        end: CGPoint(x: size, y: 0),
        options: []
    )

    // Subtle inner shadow for depth
    context.saveGState()
    context.addPath(bgPath)
    context.replacePathWithStrokedPath()
    context.setStrokeColor(CGColor(gray: 0, alpha: 0.08))
    context.setLineWidth(size * 0.02)
    context.strokePath()
    context.restoreGState()

    // Glass waveform puck (centered)
    let puckSize = size * 0.50
    let puckRect = CGRect(
        x: (size - puckSize) / 2,
        y: (size - puckSize) / 2,
        width: puckSize,
        height: puckSize
    )
    let puckRadius = puckSize * 0.28

    let puckPath = CGPath(
        roundedRect: puckRect,
        cornerWidth: puckRadius,
        cornerHeight: puckRadius,
        transform: nil
    )

    // Drop shadow under puck
    context.saveGState()
    context.setShadow(
        offset: CGSize(width: 0, height: -size * 0.015),
        blur: size * 0.04,
        color: CGColor(gray: 0, alpha: 0.25)
    )
    context.addPath(puckPath)
    context.setFillColor(CGColor(gray: 1, alpha: 0.18))
    context.fillPath()
    context.restoreGState()

    // Frosted glass fill — semi-transparent white over a slight blur shape
    context.saveGState()
    context.addPath(puckPath)
    context.clip()
    context.setFillColor(CGColor(gray: 1, alpha: 0.22))
    context.fill(puckRect)

    // Top highlight (specular sheen)
    let topHighlight = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [
            CGColor(gray: 1, alpha: 0.35),
            CGColor(gray: 1, alpha: 0.0)
        ] as CFArray,
        locations: [0, 1]
    )!
    context.drawLinearGradient(
        topHighlight,
        start: CGPoint(x: puckRect.midX, y: puckRect.maxY),
        end: CGPoint(x: puckRect.midX, y: puckRect.midY + puckRect.height * 0.1),
        options: []
    )

    // Three vertical waveform bars (white, frosted)
    let barCount = 3
    let barWidth = puckSize * 0.10
    let barSpacing = puckSize * 0.06
    let totalWidth = CGFloat(barCount) * barWidth + CGFloat(barCount - 1) * barSpacing
    let barX0 = puckRect.midX - totalWidth / 2

    let barHeights: [CGFloat] = [0.42, 0.62, 0.42]  // middle tallest

    context.setFillColor(CGColor(gray: 1, alpha: 0.95))
    for i in 0..<barCount {
        let barH = puckSize * barHeights[i]
        let x = barX0 + CGFloat(i) * (barWidth + barSpacing)
        let y = puckRect.midY - barH / 2
        let barRect = CGRect(x: x, y: y, width: barWidth, height: barH)
        let barPath = CGPath(
            roundedRect: barRect,
            cornerWidth: barWidth / 2,
            cornerHeight: barWidth / 2,
            transform: nil
        )
        context.addPath(barPath)
        context.fillPath()
    }

    // Outer glass border
    context.setStrokeColor(CGColor(gray: 1, alpha: 0.45))
    context.setLineWidth(size * 0.005)
    context.addPath(puckPath)
    context.strokePath()

    context.restoreGState()
    context.restoreGState()
}

// MARK: - Render

func renderPNG(pixelSize: Int) -> Data? {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let context = CGContext(
        data: nil,
        width: pixelSize,
        height: pixelSize,
        bitsPerComponent: 8,
        bytesPerRow: pixelSize * 4,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }

    drawIcon(into: context, pixelSize: pixelSize)

    guard let image = context.makeImage() else { return nil }
    let rep = NSBitmapImageRep(cgImage: image)
    return rep.representation(using: .png, properties: [:])
}

// MARK: - Contents.json for the asset catalog

func contentsJSON() -> String {
    let entries: [String] = sizes.map { entry in
        let base = String(Int(entry.size))
        return """
            {
              "size": "\(base)x\(base)",
              "idiom": "mac",
              "filename": "\(entry.filename)",
              "scale": "\(entry.scale)x"
            }
        """
    }

    return """
    {
      "images": [
    \(entries.joined(separator: ",\n"))
      ],
      "info": {
        "version": 1,
        "author": "jose"
      }
    }
    """
}

// MARK: - Main

let cwd = FileManager.default.currentDirectoryPath
let outDir = URL(fileURLWithPath: cwd)
    .appendingPathComponent("Resources")
    .appendingPathComponent("Assets.xcassets")
    .appendingPathComponent("AppIcon.appiconset")

try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

for entry in sizes {
    guard let png = renderPNG(pixelSize: entry.pixelSize) else {
        print("error: failed to render \(entry.filename)")
        exit(1)
    }
    let url = outDir.appendingPathComponent(entry.filename)
    try png.write(to: url)
    print("wrote \(entry.filename) (\(entry.pixelSize)px)")
}

let contentsURL = outDir.appendingPathComponent("Contents.json")
try contentsJSON().write(to: contentsURL, atomically: true, encoding: .utf8)
print("wrote Contents.json")
