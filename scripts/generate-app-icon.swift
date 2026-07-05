import AppKit
import Foundation

guard CommandLine.arguments.count == 2 else {
    fputs("usage: generate-app-icon.swift OUTPUT.icns\n", stderr)
    exit(64)
}

let outputURL = URL(fileURLWithPath: CommandLine.arguments[1])
let fileManager = FileManager.default
let temporaryRoot = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("mhp-iconset-\(UUID().uuidString)")
let iconsetURL = temporaryRoot.appendingPathComponent("MHP.iconset")

do {
    try fileManager.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

    let entries: [(String, CGFloat)] = [
        ("icon_16x16.png", 16),
        ("icon_16x16@2x.png", 32),
        ("icon_32x32.png", 32),
        ("icon_32x32@2x.png", 64),
        ("icon_128x128.png", 128),
        ("icon_128x128@2x.png", 256),
        ("icon_256x256.png", 256),
        ("icon_256x256@2x.png", 512),
        ("icon_512x512.png", 512),
        ("icon_512x512@2x.png", 1024),
    ]

    for entry in entries {
        let image = renderIcon(size: entry.1)
        try writePNG(image: image, to: iconsetURL.appendingPathComponent(entry.0))
    }

    try? fileManager.removeItem(at: outputURL)

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
    process.arguments = ["-c", "icns", iconsetURL.path, "-o", outputURL.path]
    try process.run()
    process.waitUntilExit()

    if process.terminationStatus != 0 {
        throw RuntimeError("iconutil failed with status \(process.terminationStatus)")
    }
} catch {
    fputs("failed to generate app icon: \(error)\n", stderr)
    try? fileManager.removeItem(at: temporaryRoot)
    exit(1)
}

try? fileManager.removeItem(at: temporaryRoot)

struct RuntimeError: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}

func renderIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size), flipped: true) { rect in
        let scale = rect.width / 1024
        let background = NSBezierPath(
            roundedRect: rect.insetBy(dx: 88 * scale, dy: 88 * scale),
            xRadius: 208 * scale,
            yRadius: 208 * scale
        )
        NSColor(calibratedRed: 0.52, green: 0.68, blue: 0.65, alpha: 1).setFill()
        background.fill()

        let glyphRect = NSRect(
            x: rect.minX + 248 * scale,
            y: rect.minY + 166 * scale,
            width: 528 * scale,
            height: 692 * scale
        )
        let phone = NSBezierPath(
            roundedRect: glyphRect,
            xRadius: 118 * scale,
            yRadius: 118 * scale
        )
        NSColor.white.setFill()
        phone.fill()

        NSColor(calibratedRed: 0.52, green: 0.68, blue: 0.65, alpha: 1).set()
        drawHotspotMark(in: glyphRect, lineWidth: 74 * scale)

        return true
    }

    image.size = NSSize(width: size, height: size)
    return image
}

func drawHotspotMark(in rect: NSRect, lineWidth: CGFloat) {
    let center = NSPoint(x: rect.minX + rect.width * 0.258, y: rect.minY + rect.height * 0.686)
    let dotRadius = rect.width * 0.085
    NSBezierPath(
        ovalIn: NSRect(
            x: center.x - dotRadius,
            y: center.y - dotRadius,
            width: dotRadius * 2,
            height: dotRadius * 2
        )
    ).fill()

    for radius in [rect.width * 0.237, rect.width * 0.475] {
        let arc = NSBezierPath()
        arc.appendArc(
            withCenter: center,
            radius: radius,
            startAngle: -90,
            endAngle: 0,
            clockwise: false
        )
        arc.lineWidth = lineWidth
        arc.lineCapStyle = .round
        arc.stroke()
    }
}

func writePNG(image: NSImage, to url: URL) throws {
    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:]) else {
        throw RuntimeError("failed to encode PNG")
    }

    try png.write(to: url)
}
