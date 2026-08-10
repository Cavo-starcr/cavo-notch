import AppKit
import SwiftUI

/// Everything about how the panel looks and moves, in one place, persisted.
///
/// Kept apart from `NotchViewModel` because it outlives any single panel: the
/// geometry is rebuilt when displays change and the view model goes with it,
/// while a chosen accent colour must not.
///
/// Read through `Theme`, which is what the views actually touch — that way a new
/// setting is added here and picked up everywhere without threading a parameter
/// through every view.
@MainActor
final class Appearance: ObservableObject {
    static let shared = Appearance()

    // MARK: - Choices

    /// The outline around the panel.
    ///
    /// Present at all only because the panel is a black shape on a black notch:
    /// on a dark wallpaper its lower edge can vanish, and an edge you cannot
    /// find is an edge you cannot aim at.
    enum Border: String, CaseIterable, Identifiable {
        case none, hairline, glow, gradient
        var id: String { rawValue }

        var title: String {
            switch self {
            case .none: return localized("None")
            case .hairline: return localized("Hairline")
            case .glow: return localized("Glow")
            case .gradient: return localized("Moving gradient")
            }
        }
    }

    /// Where the accent colour comes from.
    enum Accent: String, CaseIterable, Identifiable {
        case blue, teal, violet, amber, mono, artwork
        var id: String { rawValue }

        var title: String {
            switch self {
            case .blue: return localized("Blue")
            case .teal: return localized("Teal")
            case .violet: return localized("Violet")
            case .amber: return localized("Amber")
            case .mono: return localized("Mono")
            case .artwork: return localized("From artwork")
            }
        }

        /// The fixed colours. `.artwork` has none of its own — it borrows from
        /// what is playing and falls back here when nothing is.
        var color: Color {
            switch self {
            case .blue: return Color(red: 0.039, green: 0.400, blue: 1.000)
            case .teal: return Color(red: 0.000, green: 0.760, blue: 0.659)
            case .violet: return Color(red: 0.545, green: 0.361, blue: 0.965)
            case .amber: return Color(red: 1.000, green: 0.722, blue: 0.278)
            case .mono: return Color.white.opacity(0.92)
            case .artwork: return Color(red: 0.039, green: 0.400, blue: 1.000)
            }
        }
    }

    /// How much the interface moves.
    ///
    /// The names are about restraint, not speed: even `.max` keeps the panel's
    /// own open under 300 ms, because that one is seen dozens of times a day and
    /// a showy version of it turns into a tax. What grows with the level is the
    /// decoration around rare events — a track changing, a timer finishing.
    enum Motion: String, CaseIterable, Identifiable {
        case calm, normal, max
        var id: String { rawValue }

        var title: String {
            switch self {
            case .calm: return localized("Calm")
            case .normal: return localized("Normal")
            case .max: return localized("Maximum")
            }
        }
    }

    /// What the panel is made of.
    enum Material: String, CaseIterable, Identifiable {
        case solid, glass
        var id: String { rawValue }

        var title: String {
            switch self {
            case .solid: return localized("Solid black")
            case .glass: return localized("Glass")
            }
        }
    }

    // MARK: - State

    @Published var border: Border { didSet { save(border.rawValue, "appearance.border") } }
    @Published var accent: Accent { didSet { save(accent.rawValue, "appearance.accent") } }
    @Published var motion: Motion { didSet { save(motion.rawValue, "appearance.motion") } }
    @Published var material: Material { didSet { save(material.rawValue, "appearance.material") } }

    /// Now Playing in the *collapsed* notch, the way the Dynamic Island does it.
    ///
    /// Off by default, and the one setting with a real cost attached: a strip
    /// that shows a moving equaliser is animation while nobody has asked for
    /// anything, which is exactly what "0 % CPU at rest" used to mean. Whoever
    /// turns it on should get it; whoever cares about the battery should not have
    /// it chosen for them.
    @Published var liveMusic: Bool { didSet { UserDefaults.standard.set(liveMusic, forKey: "appearance.liveMusic") } }

    /// The accent as it should be drawn right now: the artwork's colour when that
    /// mode is on and something is playing, the fixed choice otherwise. Set by
    /// `MediaController` through `NotchViewModel`; nothing reads the artwork here.
    @Published var artworkAccent: Color?

    private init() {
        let d = UserDefaults.standard
        border = Border(rawValue: d.string(forKey: "appearance.border") ?? "") ?? .hairline
        accent = Accent(rawValue: d.string(forKey: "appearance.accent") ?? "") ?? .blue
        motion = Motion(rawValue: d.string(forKey: "appearance.motion") ?? "") ?? .normal
        material = Material(rawValue: d.string(forKey: "appearance.material") ?? "") ?? .solid
        liveMusic = d.bool(forKey: "appearance.liveMusic")
    }

    private func save(_ value: String, _ key: String) {
        UserDefaults.standard.set(value, forKey: key)
    }

    // MARK: - Derived: colour

    var tint: Color {
        if accent == .artwork, let artworkAccent { return artworkAccent }
        return accent.color
    }

    // MARK: - Derived: the system's word on motion and transparency
    //
    // macOS has both settings, and they are not suggestions. Reduced motion does
    // not mean *no* feedback — it means the gentle, non-vestibular kind — so
    // opacity still changes while travel and overshoot go away.

    var systemReducesMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    var systemReducesTransparency: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
    }

    /// The level actually in force, after the system has had its say.
    var effectiveMotion: Motion { systemReducesMotion ? .calm : motion }

    /// Glass is refused when the system asks for less transparency: a frosted
    /// panel over a busy desktop is precisely what that setting exists to stop.
    var effectiveMaterial: Material { systemReducesTransparency ? .solid : material }

    // MARK: - Derived: springs
    //
    // Apple's own numbers, from the fluid-interfaces talk: a drawer is damping
    // 0.8 / response 0.3, a reposition is damping 1.0 / response 0.4. The panel
    // unfolding *is* a drawer, so it keeps a little overshoot at normal and above
    // — and loses it entirely at calm, where overshoot is the first thing to go.

    /// The unfold. Interruptible by construction: SwiftUI springs animate from
    /// the presentation value, so a pointer that leaves halfway reverses from
    /// where the panel actually is rather than snapping to the target first.
    var openAnimation: Animation {
        switch effectiveMotion {
        case .calm: return .spring(response: 0.24, dampingFraction: 1.0)
        case .normal: return .spring(response: 0.27, dampingFraction: 0.82)
        case .max: return .spring(response: 0.30, dampingFraction: 0.70)
        }
    }

    /// Content arriving inside the panel. No bounce at any level: nothing threw
    /// it, and overshoot on something that merely appeared reads as a twitch.
    var contentAnimation: Animation {
        switch effectiveMotion {
        case .calm: return .easeOut(duration: 0.12)
        case .normal: return .easeOut(duration: 0.16)
        case .max: return .easeOut(duration: 0.20)
        }
    }

    /// Per-item delay when several things arrive together. Zero at calm; short
    /// everywhere else, because a long cascade is just a slow interface.
    var stagger: Double {
        switch effectiveMotion {
        case .calm: return 0
        case .normal: return 0.035
        case .max: return 0.055
        }
    }

    /// Decoration around rare events — a track changing, a timer ringing. This is
    /// where a level is allowed to be generous, since nobody sees it fifty times
    /// an hour.
    var flourishAnimation: Animation {
        switch effectiveMotion {
        case .calm: return .easeOut(duration: 0.18)
        case .normal: return .spring(response: 0.35, dampingFraction: 0.75)
        case .max: return .spring(response: 0.45, dampingFraction: 0.58)
        }
    }

    /// Whether continuously running decoration is allowed at all: the equaliser,
    /// the marquee, the travelling gradient. Calm means the interface holds
    /// still unless something happened.
    var allowsPerpetualMotion: Bool { effectiveMotion != .calm }

    // MARK: - Derived: surface

    var panelFill: Color {
        effectiveMaterial == .glass ? Color.black.opacity(0.55) : Color.black
    }

    var usesGlass: Bool { effectiveMaterial == .glass }

    /// A bigger surface should read as thicker: the open panel gets a deeper
    /// shadow than the collapsed strip, not the same one scaled.
    func shadowRadius(open: Bool) -> CGFloat { open ? 18 : 10 }
}
