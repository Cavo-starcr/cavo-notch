import SwiftUI

/// What the views actually read.
///
/// The animations forward to `Appearance`, where the user's motion level and the
/// system's reduce-motion setting have already been folded in — so every one of
/// the call sites scattered through the panes obeys both without knowing either
/// exists. The colours that do not depend on a choice stay as plain constants.
@MainActor
enum Theme {
    static var openAnimation: Animation { Appearance.shared.openAnimation }
    static var contentAnimation: Animation { Appearance.shared.contentAnimation }
    /// Pane switching: the outgoing pane leaves faster than the incoming one
    /// arrives, so the two are never both half-visible for long.
    static var paneAnimation: Animation { Appearance.shared.contentAnimation }
    static var paneIn: Animation { Appearance.shared.contentAnimation.delay(0.04) }
    static var paneOut: Animation { .easeIn(duration: 0.12) }
    static var artworkAnimation: Animation { Appearance.shared.flourishAnimation }

    /// The accent, after the artwork mode and fallbacks have had their say.
    static var tint: Color { Appearance.shared.tint }

    static let collapsedTopRadius: CGFloat = 6
    static let collapsedBottomRadius: CGFloat = 9
    static let openTopRadius: CGFloat = 12
    static let openBottomRadius: CGFloat = 22

    static let secondary = Color.white.opacity(0.55)
    static let tertiary = Color.white.opacity(0.32)
    static let surface = Color.white.opacity(0.08)
    static let surfaceHover = Color.white.opacity(0.14)
    static let hairline = Color.white.opacity(0.10)
}

/// Flat, focus-free button used for every control in the panel.
struct NotchButtonStyle: ButtonStyle {
    var size: CGFloat = 26
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: prominent ? 17 : 13, weight: .medium))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(
                Circle().fill(prominent ? Theme.surfaceHover : Color.clear)
            )
            // Pressed state is feedback, not decoration: a slight sink reads as
            // "heard you" the way opacity alone never quite does.
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .opacity(configuration.isPressed ? 0.7 : 1)
            .contentShape(Circle())
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

extension View {
    /// Tracks hover without triggering layout changes in the parent.
    func onHoverChange(_ action: @escaping (Bool) -> Void) -> some View {
        onHover(perform: action)
    }
}

func formatTime(_ seconds: TimeInterval) -> String {
    guard seconds.isFinite, seconds >= 0 else { return "--:--" }
    let total = Int(seconds.rounded())
    return String(format: "%d:%02d", total / 60, total % 60)
}
