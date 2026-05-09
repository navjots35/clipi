// make-icon.swift — renders clipi's app icon at every size macOS expects in
// an `.iconset`, then leaves it on disk for `iconutil` to pack into `.icns`.
//
// Usage:  swift scripts/make-icon.swift [output-iconset-dir]
//
// Defaults to `Resources/clipi.iconset`. Re-run any time you want to refresh
// the icon — the result is fully deterministic (no fonts, no system images).

import AppKit
import CoreGraphics

@discardableResult
func renderIcon(size: CGFloat) -> NSImage {
    let img = NSImage(size: NSSize(width: size, height: size))
    img.lockFocus()
    defer { img.unlockFocus() }
    guard let ctx = NSGraphicsContext.current else { return img }
    ctx.imageInterpolation = .high

    // macOS Big Sur+ icon convention: ~80% interior, ~10% padding each side,
    // squircle radius ≈ 22.5% of the inner box width. Matches the rounded
    // rect the system applies to system icons.
    let pad = size * 0.10
    let inner = NSRect(x: pad, y: pad, width: size - 2 * pad, height: size - 2 * pad)
    let cornerRadius = inner.width * 0.225

    // Body: blue → indigo gradient matching the design's onboarding tile.
    let body = NSBezierPath(roundedRect: inner, xRadius: cornerRadius, yRadius: cornerRadius)
    NSGraphicsContext.saveGraphicsState()
    body.addClip()
    let gradient = NSGradient(colors: [
        NSColor(srgbRed: 0.039, green: 0.518, blue: 1.000, alpha: 1.0),   // #0A84FF
        NSColor(srgbRed: 0.369, green: 0.361, blue: 0.902, alpha: 1.0)    // #5E5CE6
    ])!
    gradient.draw(in: inner, angle: 135)

    // Top inner highlight — gives the icon a "lit from above" softness.
    let highlight = NSGradient(colors: [
        NSColor.white.withAlphaComponent(0.22),
        NSColor.white.withAlphaComponent(0.0)
    ])!
    highlight.draw(in: inner, angle: 90)
    NSGraphicsContext.restoreGraphicsState()

    // Edge highlight stroke.
    NSColor.white.withAlphaComponent(0.30).setStroke()
    body.lineWidth = max(1, size * 0.006)
    body.stroke()

    // Clipboard glyph — two overlapping rounded rects so the icon reads as
    // "stack of clipped pages". Front sheet is opaque white; back sheet is a
    // translucent ghost so the gradient shows through.
    let g = inner.width * 0.50           // glyph total footprint
    let cx = inner.midX
    let cy = inner.midY
    let sheetW = g * 0.66
    let sheetH = g * 0.86
    let sheetR = sheetW * 0.16
    let offset = g * 0.12

    let backFrame = NSRect(x: cx - sheetW / 2 + offset,
                           y: cy - sheetH / 2 - offset,
                           width: sheetW, height: sheetH)
    let frontFrame = NSRect(x: cx - sheetW / 2 - offset,
                            y: cy - sheetH / 2 + offset,
                            width: sheetW, height: sheetH)

    let backPath = NSBezierPath(roundedRect: backFrame, xRadius: sheetR, yRadius: sheetR)
    NSColor.white.withAlphaComponent(0.32).setFill()
    backPath.fill()
    NSColor.white.withAlphaComponent(0.55).setStroke()
    backPath.lineWidth = max(1, size * 0.006)
    backPath.stroke()

    let frontPath = NSBezierPath(roundedRect: frontFrame, xRadius: sheetR, yRadius: sheetR)
    NSColor.white.setFill()
    frontPath.fill()

    return img
}

func savePNG(_ img: NSImage, to path: String) {
    guard let tiff = img.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
        fputs("✗ failed to encode PNG for \(path)\n", stderr); exit(1)
    }
    do {
        try png.write(to: URL(fileURLWithPath: path))
    } catch {
        fputs("✗ failed to write \(path): \(error)\n", stderr); exit(1)
    }
}

// `(filename-without-extension, pixel-edge-length)` — every size the macOS
// iconset format expects, so iconutil can produce a complete .icns.
let sizes: [(String, CGFloat)] = [
    ("icon_16x16",         16),
    ("icon_16x16@2x",      32),
    ("icon_32x32",         32),
    ("icon_32x32@2x",      64),
    ("icon_128x128",      128),
    ("icon_128x128@2x",   256),
    ("icon_256x256",      256),
    ("icon_256x256@2x",   512),
    ("icon_512x512",      512),
    ("icon_512x512@2x",  1024),
]

let outDir = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "Resources/clipi.iconset"

try? FileManager.default.createDirectory(atPath: outDir,
                                         withIntermediateDirectories: true)

for (name, edge) in sizes {
    let img = renderIcon(size: edge)
    savePNG(img, to: "\(outDir)/\(name).png")
    print("✓ \(name).png  (\(Int(edge))×\(Int(edge)))")
}

print("\nNext: iconutil -c icns \"\(outDir)\" -o \(outDir.replacingOccurrences(of: ".iconset", with: ".icns"))")
