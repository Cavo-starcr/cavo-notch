#!/usr/bin/env swift
// Renders Resources/AppIcon.icns from code — no design tool in the loop.
// CAVO mark: brand-blue squircle with the notch cut out of its top edge and the
// double chevron in the middle. Drawn on a 1024 canvas and scaled down, so the
// 16pt size is the same shape rather than a separate asset that drifts.
// Usage: swift Scripts/make-icon.swift <output.icns>
import AppKit

let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.icns"
let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("CAVONotch.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func draw(size s: CGFloat) -> NSBitmapImageRep {
    let px = Int(s)
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    let k = s / 1024  // everything below is authored on a 1024 canvas

    // Rounded-square body, macOS proportions.
    let body = CGRect(x: 100 * k, y: 100 * k, width: 824 * k, height: 824 * k)
    let squircle = CGPath(roundedRect: body, cornerWidth: 185 * k, cornerHeight: 185 * k, transform: nil)
    ctx.saveGState()
    ctx.addPath(squircle)
    ctx.clip()
    let gradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [
            CGColor(red: 0.039, green: 0.400, blue: 1.000, alpha: 1),  // brand 500 #0A66FF
            CGColor(red: 0.043, green: 0.251, blue: 0.651, alpha: 1)   // brand 700 #0B40A6
        ] as CFArray,
        locations: [0, 1]
    )!
    ctx.drawLinearGradient(
        gradient,
        start: CGPoint(x: body.midX, y: body.maxY),
        end: CGPoint(x: body.midX, y: body.minY),
        options: []
    )

    // The notch itself, cut into the top edge.
    let notchW = 330 * k, notchH = 86 * k, r = 34 * k
    let nx = body.midX - notchW / 2, ny = body.maxY - notchH
    let notch = CGMutablePath()
    notch.move(to: CGPoint(x: nx, y: body.maxY))
    notch.addLine(to: CGPoint(x: nx, y: ny + r))
    notch.addQuadCurve(to: CGPoint(x: nx + r, y: ny), control: CGPoint(x: nx, y: ny))
    notch.addLine(to: CGPoint(x: nx + notchW - r, y: ny))
    notch.addQuadCurve(to: CGPoint(x: nx + notchW, y: ny + r), control: CGPoint(x: nx + notchW, y: ny))
    notch.addLine(to: CGPoint(x: nx + notchW, y: body.maxY))
    notch.closeSubpath()
    ctx.addPath(notch)
    ctx.setFillColor(CGColor(red: 0.024, green: 0.055, blue: 0.133, alpha: 1))  // navy 950 #060E22
    ctx.fillPath()

    // The CAVO double chevron. Stroked rather than filled: one path, and the cap
    // shape stays right at every size instead of the joins going ragged at 16pt.
    let cx = body.midX, cy = body.midY - 24 * k
    let arm = 112 * k          // horizontal reach of one chevron
    let rise = 142 * k         // half-height
    let gap = 176 * k          // distance between the two — wide enough that the
                               // two stay separate marks at 16pt instead of merging
    ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.97))
    ctx.setLineWidth(64 * k)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    for offset in [-gap / 2 - arm / 2, gap / 2 - arm / 2] {
        let x = cx + offset
        let path = CGMutablePath()
        path.move(to: CGPoint(x: x, y: cy + rise))
        path.addLine(to: CGPoint(x: x + arm, y: cy))
        path.addLine(to: CGPoint(x: x, y: cy - rise))
        ctx.addPath(path)
        ctx.strokePath()
    }
    ctx.restoreGState()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

for (size, name) in [
    (16, "icon_16x16"), (32, "icon_16x16@2x"), (32, "icon_32x32"), (64, "icon_32x32@2x"),
    (128, "icon_128x128"), (256, "icon_128x128@2x"), (256, "icon_256x256"), (512, "icon_256x256@2x"),
    (512, "icon_512x512"), (1024, "icon_512x512@2x")
] {
    let data = draw(size: CGFloat(size)).representation(using: .png, properties: [:])!
    try data.write(to: iconset.appendingPathComponent("\(name).png"))
}

let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", outPath]
try task.run()
task.waitUntilExit()
print(task.terminationStatus == 0 ? "wrote \(outPath)" : "iconutil failed")
