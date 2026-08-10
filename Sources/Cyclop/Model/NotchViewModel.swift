import AppKit
import Combine

@MainActor
final class NotchViewModel: ObservableObject {
    enum Tab: String, CaseIterable, Identifiable {
        case media, shelf, clipboard, snippets, calendar, translate, notes, timer
        var id: String { rawValue }

        var symbol: String {
            switch self {
            case .media: return "music.note"
            case .shelf: return "tray.full.fill"
            case .clipboard: return "list.clipboard.fill"
            case .snippets: return "pin.fill"
            case .calendar: return "calendar"
            case .translate: return "translate"
            case .notes: return "note.text"
            case .timer: return "timer"
            }
        }

        var title: String {
            switch self {
            case .media: return localized("Music")
            case .shelf: return localized("Shelf")
            case .clipboard: return localized("Clipboard")
            case .snippets: return localized("Snippets")
            case .calendar: return localized("Calendar")
            case .translate: return localized("Translate")
            case .notes: return localized("Notes")
            case .timer: return localized("Timer")
            }
        }

        /// Tabs that want the keyboard when landed on.
        ///
        /// Three of them have a field in them, so arriving and typing is a
        /// single move. The shelf has no field and is here for one key: space,
        /// for Quick Look, the way it works in Finder. That is a deliberate
        /// trade — the panel taking key status stops the insertion point
        /// blinking in whatever is underneath, and the shelf is a tab one
        /// arrives at to drag rather than to type. Worth it for the preview.
        var needsKeyboard: Bool {
            self == .translate || self == .snippets || self == .notes || self == .shelf
        }

        /// Which rail the icon sits on. The left one carries the original six
        /// and is full — a seventh icon would outgrow the height the panel
        /// body has — so growth continues in a second column on the right,
        /// which the scratch notes open and the timer now shares.
        static let leftRail: [Tab] = [.media, .shelf, .clipboard, .snippets, .calendar, .translate]
        static let rightRail: [Tab] = [.notes, .timer]
    }

    @Published var isOpen = false
    @Published var isDropTargeted = false
    @Published var tab: Tab = .media {
        didSet {
            // Opening the tab only re-checks the status. The permission prompt
            // is the user's own press on the button inside the pane: this is
            // the one permission Cyclop asks for at all, and it deserves an
            // explanation before the system dialog, not after.
            if tab == .calendar { calendar.refreshAccess() }
            // The snippets file is edited from outside the app, so it is read
            // on the way in rather than held from launch.
            if tab == .snippets { snippets.reload() }
            // Leaving the notes sweeps out the blank ones — they cost one
            // hover to recreate, and a trail of empty cards is the clutter a
            // scratchpad exists to avoid.
            if oldValue == .notes, tab != .notes { notes.leave() }
            // Leaving the tab that types gives the keyboard straight back.
            if !tab.needsKeyboard { wantsKeyboard = false }
        }
    }

    /// Whether the panel currently holds the keyboard.
    ///
    /// Tracked apart from `tab` because the two come apart in one direction:
    /// clicking into another app drops the claim without changing which tab is
    /// showing, so the text one was typing survives and the panel is free to
    /// collapse. Landing on a tab that types always raises it again — there is
    /// no such thing as a panel that shows a field but cannot receive a key.
    @Published var wantsKeyboard = false

    let geometry: NotchGeometry
    let media: MediaController
    let shelf: ShelfStore
    let clipboard: ClipboardStore
    let calendar: CalendarStore
    let translator: Translator
    let snippets: SnippetStore
    let notes: NoteStore
    let timer = CountdownTimer()
    let weather = WeatherService.shared
    /// Shared by every pane that shows something worth not showing.
    let privacy = PrivacyMode()

    private var cancellables = Set<AnyCancellable>()

    init(geometry: NotchGeometry) {
        self.geometry = geometry
        self.media = MediaController()
        self.shelf = ShelfStore()
        self.clipboard = ClipboardStore()
        self.calendar = CalendarStore()
        self.translator = Translator()
        self.snippets = SnippetStore()
        self.notes = NoteStore()

        // The panel header reads through to the stores — counters, the source
        // name, the equalizer. Nested ObservableObjects do not propagate on
        // their own, so those would only refresh when something else happened
        // to redraw the view.
        //
        // Forwarded only while the panel is open. Collapsed, there is nothing
        // these redraws could change — the panel is a black shape — yet the
        // stores keep their own schedule: a track change every few minutes, a
        // copy whenever one happens, and each send re-evaluated the whole
        // view for nobody. Opening repaints from the stores directly, because
        // `isOpen` is itself @Published and its own send does that.
        //
        // The stores with a text field in their pane — the translator, the
        // snippets and the notes — are deliberately absent. They change on every
        // keystroke, and redrawing the whole panel per letter costs more than a
        // stale counter: it rebuilds the field, which drops the focus, so the
        // first letter typed is also the last one that lands. Their panes
        // observe them directly, and the header counter refreshes anyway,
        // because the list is only ever re-read on the way into the tab.
        for child in [
            media.objectWillChange,
            shelf.objectWillChange,
            clipboard.objectWillChange,
            calendar.objectWillChange,
        ] {
            child
                .sink { [weak self] _ in
                    guard let self, self.isOpen || self.isDropTargeted else { return }
                    self.objectWillChange.send()
                }
                .store(in: &cancellables)
        }

        // The collapsed strip is the one thing that draws while the panel is
        // closed, so media changes must reach the view even then — but only
        // while the switch is on: with it off, the old "collapsed panel is a
        // black shape, no redraws" contract stands untouched.
        media.objectWillChange
            .sink { [weak self] _ in
                guard let self, !self.isOpen, Appearance.shared.liveMusic else { return }
                self.objectWillChange.send()
            }
            .store(in: &cancellables)

        // The accent that follows the artwork. Derived here, off the artwork
        // publisher, so the appearance store never has to know what artwork is.
        media.$artwork
            .receive(on: RunLoop.main)
            .sink { artwork in
                Appearance.shared.artworkAccent = artwork?.accentColor
            }
            .store(in: &cancellables)

        // Flipping any appearance switch repaints the panel — including the
        // strip appearing or vanishing when Live Music is toggled while closed.
        Appearance.shared.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        // A weather reading lands about three times an hour; repainting the
        // collapsed strip for it is the cheapest redraw in the app.
        weather.objectWillChange
            .sink { [weak self] _ in
                guard let self, !self.isOpen else { return }
                self.objectWillChange.send()
            }
            .store(in: &cancellables)
    }

    /// The collapsed-notch music strip: on, playing, and the panel closed.
    ///
    /// The one place the resting notch is allowed to be more than a black
    /// rectangle, and only because the owner flipped the switch that says so.
    var musicStripActive: Bool {
        !isOpen && !isDropTargeted && Appearance.shared.liveMusic && media.track != nil
    }

    /// Weather on the wings, when its switch is on and there is a reading.
    /// Music outranks it: a track is something happening, weather merely is.
    var weatherStripActive: Bool {
        !isOpen && !isDropTargeted && !musicStripActive
            && weather.enabled && weather.reading != nil
    }

    var stripActive: Bool { musicStripActive || weatherStripActive }

    /// Size of the visible body for the current state.
    var bodySize: CGSize {
        if isOpen || isDropTargeted { return geometry.expandedSize }
        if stripActive {
            // Wings wide enough for a 17 pt artwork and the meter, and a chin a
            // few points deeper than the cutout — the droop is what makes it
            // read as an island rather than a stretched notch.
            return CGSize(width: geometry.notchSize.width + 128, height: geometry.notchSize.height + 6)
        }
        return geometry.notchSize
    }

    /// Off switch for people who copy images all day and do not want them kept.
    static let saveClipboardImagesKey = "saveClipboardImages"

    /// Defaults to on: the feature is the reason the folder exists.
    static var saveClipboardImagesEnabled: Bool {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: saveClipboardImagesKey) != nil else { return true }
        return defaults.bool(forKey: saveClipboardImagesKey)
    }

    /// Hover and click both land here. A tab that types takes the keyboard
    /// either way: showing a field one cannot type into is worse than briefly
    /// dimming the caret of the window underneath, and the dwell threshold on
    /// the rail already keeps a passing pointer from arriving here at all.
    func select(_ tab: Tab) {
        self.tab = tab
        if tab.needsKeyboard { wantsKeyboard = true }
    }

    func start() {
        media.start()
        shelf.load()
        snippets.reload()
        // Only picks up where it left off if access was granted earlier; it
        // never prompts on its own.
        calendar.start()
        // A countdown outlives a relaunch, but only if it is still due — see
        // `restore()` for why a lapsed one is dropped without a sound.
        timer.restore()

        // Screenshots reach the shelf through here whether they were taken on
        // this Mac or on a phone: a copy made on the phone arrives in the same
        // pasteboard, carried over by Continuity.
        //
        // The switch is asked by the store before it touches image data, not
        // here after the fact: turned off, a copied picture used to be encoded
        // to PNG in full just to be dropped on this doorstep — pure heat on
        // exactly the machines whose owners turned the feature off.
        clipboard.wantsImages = { Self.saveClipboardImagesEnabled }
        clipboard.onImage = { [weak self] png in
            guard let self, let url = ScreenshotVault.save(png) else { return }
            self.shelf.add([url])
            self.tab = .shelf
        }
        clipboard.start()
    }

    func stop() {
        media.stop()
        clipboard.stop()
        calendar.stop()
        // Whatever was typed makes it to disk even when quitting mid-thought.
        notes.flush()
        // Leaves the due date on disk: quitting is not cancelling, and a timer
        // with minutes left is picked up again on the next launch. Only the
        // ticking stops.
        timer.suspend()
    }

    /// A bare key press inside the panel. Returns whether it was consumed.
    ///
    /// Physical key codes, not characters — same reason `NotchPanel` matches the
    /// editing shortcuts that way: a Cyrillic layout prints different characters
    /// from the same keys, and the space bar is at code 49 in every layout there
    /// is.
    func handleKeyDown(_ event: NSEvent) -> Bool {
        // Nothing bare while a modifier is down: those belong to the shortcuts.
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags.subtracting(.function).isEmpty else { return false }
        guard tab == .shelf, event.keyCode == 49 else { return false }
        shelf.previewFromKeyboard()
        return true
    }

    func accept(urls: [URL]) -> Bool {
        shelf.add(urls)
        tab = .shelf
        return true
    }
}
