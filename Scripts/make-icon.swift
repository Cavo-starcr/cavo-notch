#!/usr/bin/env swift
// Renders Resources/AppIcon.icns from code — no design tool in the loop.
// Usage: swift Scripts/make-icon.swift <output.icns>
//
// The mark is the app's own silhouette: the panel as it hangs out of the notch,
// with the concave shoulders that melt into the top edge of the display. Same
// geometry as `NotchShape` in the UI, kept in step by hand. A logo that is
// literally the shape of the thing it names needs no explaining, and it tells
// this product apart from the studio's other tools, which carry the chevron.
//
// Drawn on a 1024 canvas and scaled down, so 16 pt is the same shape rather than
// a separate asset that drifts.
import AppKit

let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.icns"
let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("CAVONotch.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

/// The panel silhouette. `tr` is the concave shoulder, and the body is inset by
/// it on both sides — the same contract `NotchShape` has in the UI.
func notchPath(in rect: CGRect, topRadius tr: CGFloat, bottomRadius br: CGFloat) -> CGPath {
    let left = rect.minX + tr
    let right = rect.maxX - tr
    let p = CGMutablePath()
    // Quartz has y growing upwards, so the panel's top edge is maxY.
    p.move(to: CGPoint(x: rect.minX, y: rect.maxY))
    p.addQuadCurve(to: CGPoint(x: left, y: rect.maxY - tr), control: CGPoint(x: left, y: rect.maxY))
    p.addLine(to: CGPoint(x: left, y: rect.minY + br))
    p.addQuadCurve(to: CGPoint(x: left + br, y: rect.minY), control: CGPoint(x: left, y: rect.minY))
    p.addLine(to: CGPoint(x: right - br, y: rect.minY))
    p.addQuadCurve(to: CGPoint(x: right, y: rect.minY + br), control: CGPoint(x: right, y: rect.minY))
    p.addLine(to: CGPoint(x: right, y: rect.maxY - tr))
    p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.maxY), control: CGPoint(x: right, y: rect.maxY))
    p.closeSubpath()
    return p
}

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
    let k = s / 1024  // authored on a 1024 canvas

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

    // The strip the panel hangs from — the top edge of a display. Without it the
    // silhouette below reads as a plain tab instead of something cut into an edge.
    let barH = 140 * k
    ctx.setFillColor(CGColor(red: 0.024, green: 0.055, blue: 0.133, alpha: 1))  // navy 950
    ctx.fill(CGRect(x: body.minX, y: body.maxY - barH, width: body.width, height: barH))

    // The panel, unfolded out of that strip. Its top edge starts inside the strip
    // so the shoulders have something to melt into, exactly as the real panel
    // overlaps the menu bar.
    // Wide and shallow, in the proportion the real panel has (620 × 208). A
    // portrait silhouette here read as a drinking glass, not as a panel.
    let panelW = 600 * k
    let tr = 84 * k                     // concave shoulder
    let br = 104 * k                    // rounded bottom
    let panelTop = body.maxY - barH * 0.28
    let panelBottom = body.minY + 300 * k
    let placed = CGRect(
        x: body.midX - panelW / 2,
        y: panelBottom,
        width: panelW,
        height: panelTop - panelBottom
    )
    ctx.addPath(notchPath(in: placed, topRadius: tr, bottomRadius: br))
    ctx.setFillColor(CGColor(gray: 1, alpha: 1))
    ctx.fillPath()

    // What the panel holds: a rail of tab dots and the content beside it. Skipped
    // below 128 px — at 32 and 16 these turn to grey mush and the silhouette
    // reads better clean.
    if s >= 128 {
        let inset = 92 * k
        let d = 44 * k, gap = 30 * k
        let railX = placed.minX + inset
        let top = placed.maxY - barH * 0.55 - 96 * k
        ctx.setFillColor(CGColor(red: 0.039, green: 0.400, blue: 1.000, alpha: 0.32))
        var y = top
        for _ in 0..<2 {
            ctx.fillEllipse(in: CGRect(x: railX, y: y, width: d, height: d))
            y -= d + gap
        }
        let blockX = railX + d + 48 * k
        let blockW = placed.maxX - inset - blockX
        var by = top
        for (i, frac) in [1.0, 0.62].enumerated() {
            ctx.setFillColor(CGColor(red: 0.039, green: 0.400, blue: 1.000, alpha: i == 0 ? 0.32 : 0.18))
            ctx.fill(CGRect(x: blockX, y: by, width: blockW * frac, height: d))
            by -= d + gap
        }
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
