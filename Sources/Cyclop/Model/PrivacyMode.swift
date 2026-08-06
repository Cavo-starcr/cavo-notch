import AppKit
import Combine

/// Hides what the panel holds behind a field of drifting dots, for screens that
/// somebody else is watching.
///
/// One switch for every tab rather than one per tab: three switches are three
/// ways to leave the wrong one off, and the cost of that mistake is the whole
/// point of the feature. The state outlives launches — forgetting to turn the
/// mode *on* is what costs something, so it is the one that must not depend on
/// remembering.
///
/// Nothing here decides *what* is a secret. Guessing at addresses and card
/// numbers with a regular expression fails silently and tells the user about it
/// only afterwards, on the recording; covering everything is predictable, and
/// predictability is the feature.
@MainActor
final class PrivacyMode: ObservableObject {
    static let key = "privacyMode"

    @Published var isOn: Bool {
        didSet {
            UserDefaults.standard.set(isOn, forKey: Self.key)
            if !isOn { revealed.removeAll() }
        }
    }

    /// What the user has uncovered by hand, by row id. Cleared whenever the
    /// panel folds: a row uncovered once must not still be uncovered the next
    /// time the panel opens, which would be exactly when nobody is looking at
    /// it and the camera is.
    @Published private(set) var revealed: Set<String> = []

    init() {
        isOn = UserDefaults.standard.bool(forKey: Self.key)
    }

    /// True when this particular row has to be covered right now.
    func hides(_ id: String) -> Bool {
        isOn && !revealed.contains(id)
    }

    func reveal(_ id: String) {
        revealed.insert(id)
    }

    func hide(_ id: String) {
        revealed.remove(id)
    }

    func toggle(_ id: String) {
        if revealed.contains(id) { revealed.remove(id) } else { revealed.insert(id) }
    }

    /// Back to covered — called when the panel folds.
    func coverEverything() {
        guard !revealed.isEmpty else { return }
        revealed.removeAll()
    }
}
