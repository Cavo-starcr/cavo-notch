import AppKit
import SwiftUI

/// The panel's outline, in whichever of the four treatments is chosen.
///
/// Exists because the panel is a black shape hanging from a black notch: on a
/// dark wallpaper its lower edge can vanish entirely, and an edge you cannot see
/// is an edge you cannot aim a pointer at. The hairline solves that and stops;
/// the glow and the gradient are the same edge dressed up.
struct PanelBorder: View {
    @ObservedObject var appearance: Appearance
    let topRadius: CGFloat
    let bottomRadius: CGFloat
    /// The travelling gradient runs only while the panel is open: perpetual
    /// motion on the collapsed strip would be animation nobody asked for.
    let isOpen: Bool

    var body: some View {
        switch appearance.border {
        case .none:
            EmptyView()

        case .hairline:
            shape.stroke(Color.white.opacity(0.16), lineWidth: 1)

        case .glow:
            // Two strokes, not one stroke with a big shadow: the inner line keeps
            // the edge crisp while the wider soft pass reads as light leaking out
            // from behind the panel rather than a blurry border.
            ZStack {
                shape.stroke(appearance.tint.opacity(0.55), lineWidth: 1)
                shape
                    .stroke(appearance.tint.opacity(0.35), lineWidth: 3)
                    .blur(radius: 6)
            }

        case .gradient:
            if isOpen, appearance.allowsPerpetualMotion {
                // One comet of accent light travelling the outline. Driven by a
                // timeline rather than repeatForever, so it pauses the moment the
                // view leaves the hierarchy instead of animating an off-screen shape.
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                    let phase = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 4) / 4
                    shape
                        .stroke(
                            AngularGradient(
                                stops: [
                                    .init(color: appearance.tint.opacity(0.05), location: 0),
                                    .init(color: appearance.tint, location: 0.12),
                                    .init(color: appearance.tint.opacity(0.05), location: 0.30),
                                    .init(color: appearance.tint.opacity(0.05), location: 1),
                                ],
                                center: .center,
                                angle: .degrees(phase * 360)
                            ),
                            lineWidth: 1.5
                        )
                }
            } else {
                // Collapsed, or motion is set to calm: the same accent edge, held still.
                shape.stroke(appearance.tint.opacity(0.4), lineWidth: 1)
            }
        }
    }

    private var shape: NotchShape {
        NotchShape(topRadius: topRadius, bottomRadius: bottomRadius)
    }
}

/// Desktop blur behind the panel, for the glass material.
///
/// SwiftUI's own `Material` blurs content *inside* the window, and behind this
/// panel there is nothing but a transparent window — the wallpaper can only be
/// reached through an `NSVisualEffectView` in behind-window mode.
struct BehindWindowBlur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow
        view.material = .hudWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

extension NSImage {
    /// The album art reduced to one usable accent colour.
    ///
    /// Average first — one pixel through CIAreaAverage — then pushed to a colour
    /// that can actually tint an interface: album averages trend muddy and dark,
    /// and an accent needs saturation and light to survive on black. Hue is the
    /// only thing kept as-is; hue is the identity of the artwork.
    var accentColor: Color? {
        guard let tiff = tiffRepresentation,
              let source = CIImage(data: tiff),
              let filter = CIFilter(name: "CIAreaAverage") else { return nil }
        filter.setValue(source, forKey: kCIInputImageKey)
        filter.setValue(CIVector(cgRect: source.extent), forKey: kCIInputExtentKey)
        guard let output = filter.outputImage else { return nil }

        var pixel = [UInt8](repeating: 0, count: 4)
        CIContext(options: [.workingColorSpace: kCFNull as Any]).render(
            output,
            toBitmap: &pixel,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: nil
        )
        let raw = NSColor(
            red: CGFloat(pixel[0]) / 255,
            green: CGFloat(pixel[1]) / 255,
            blue: CGFloat(pixel[2]) / 255,
            alpha: 1
        )
        guard let rgb = raw.usingColorSpace(.deviceRGB) else { return nil }
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        rgb.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return Color(hue: h, saturation: max(s, 0.55), brightness: max(b, 0.72))
    }
}
