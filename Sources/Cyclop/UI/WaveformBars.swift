import AppKit
import SwiftUI

/// The music strip's level meter: five bars breathing out of phase, drawn with
/// Core Animation rather than SwiftUI.
///
/// The distinction is where the work happens. A SwiftUI repeat-forever animation
/// re-evaluates the view on the main thread every frame; a CABasicAnimation is
/// handed once to the render server and plays there, costing the app nothing
/// after the handoff. For the one animation in this app that runs continuously
/// while the panel is *collapsed*, that difference is the whole point.
struct WaveformBars: NSViewRepresentable {
    var isPlaying: Bool
    var color: Color

    private static let barCount = 5
    private static let barWidth: CGFloat = 2.5
    private static let gap: CGFloat = 2.5
    private static let height: CGFloat = 13

    func makeNSView(context: Context) -> NSView {
        let width = CGFloat(Self.barCount) * Self.barWidth + CGFloat(Self.barCount - 1) * Self.gap
        let view = NSView(frame: NSRect(x: 0, y: 0, width: width, height: Self.height))
        view.wantsLayer = true

        // One gradient, masked by the bars: the light runs across the whole
        // meter instead of each bar carrying its own flat colour.
        let gradient = CAGradientLayer()
        gradient.frame = view.bounds
        gradient.startPoint = CGPoint(x: 0, y: 0.5)
        gradient.endPoint = CGPoint(x: 1, y: 0.5)

        let mask = CALayer()
        mask.frame = view.bounds
        for i in 0..<Self.barCount {
            let bar = CALayer()
            bar.anchorPoint = CGPoint(x: 0.5, y: 0)  // grow from the bottom
            bar.frame = CGRect(
                x: CGFloat(i) * (Self.barWidth + Self.gap),
                y: 0,
                width: Self.barWidth,
                height: Self.height * 0.3
            )
            bar.cornerRadius = Self.barWidth / 2
            bar.backgroundColor = NSColor.white.cgColor
            mask.addSublayer(bar)
        }
        gradient.mask = mask
        view.layer?.addSublayer(gradient)
        context.coordinator.gradient = gradient
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.apply(color: color, playing: isPlaying)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    @MainActor
    final class Coordinator {
        var gradient: CAGradientLayer?
        private var playing: Bool?

        func apply(color: Color, playing: Bool) {
            guard let gradient else { return }
            let base = NSColor(color)
            gradient.colors = [
                base.withAlphaComponent(0.55).cgColor,
                base.cgColor,
            ]
            guard self.playing != playing else { return }
            self.playing = playing

            let bars = gradient.mask?.sublayers ?? []
            for (i, bar) in bars.enumerated() {
                bar.removeAllAnimations()
                if playing {
                    // Out-of-phase periods, so the bars never sync up into a
                    // metronome: primes-ish durations drift against each other.
                    let anim = CABasicAnimation(keyPath: "transform.scale.y")
                    anim.fromValue = 0.25 + Double(i % 3) * 0.1
                    anim.toValue = [2.6, 3.3, 2.1, 3.0, 2.4][i % 5]
                    anim.duration = [0.42, 0.53, 0.47, 0.61, 0.5][i % 5]
                    anim.autoreverses = true
                    anim.repeatCount = .infinity
                    anim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    anim.timeOffset = Double(i) * 0.13
                    bar.add(anim, forKey: "wave")
                } else {
                    bar.transform = CATransform3DMakeScale(1, 1, 1)
                }
            }
        }
    }
}
