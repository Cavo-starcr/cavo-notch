import AppKit
import Combine

@MainActor
final class NotchViewModel: ObservableObject {
    enum Tab: String, CaseIterable, Identifiable {
        case media, shelf, clipboard, calendar
        var id: String { rawValue }

        var symbol: String {
            switch self {
            case .media: return "music.note"
            case .shelf: return "tray.full.fill"
            case .clipboard: return "list.clipboard.fill"
            case .calendar: return "calendar"
            }
        }

        var title: String {
            switch self {
            case .media: return "Музыка"
            case .shelf: return "Полка"
            case .clipboard: return "Буфер"
            case .calendar: return "Календарь"
            }
        }
    }

    @Published var isOpen = false
    @Published var isDropTargeted = false
    @Published var tab: Tab = .media {
        // Opening the tab only re-checks the status. The permission prompt is
        // the user's own press on the button inside the pane: this is the one
        // permission Cyclop asks for at all, and it deserves an explanation
        // before the system dialog, not after.
        didSet { if tab == .calendar { calendar.refreshAccess() } }
    }

    let geometry: NotchGeometry
    let media: MediaController
    let shelf: ShelfStore
    let clipboard: ClipboardStore
    let calendar: CalendarStore

    private var cancellables = Set<AnyCancellable>()

    init(geometry: NotchGeometry) {
        self.geometry = geometry
        self.media = MediaController()
        self.shelf = ShelfStore()
        self.clipboard = ClipboardStore()
        self.calendar = CalendarStore()

        // The panel header reads through to the stores — counters, the source
        // name, the equalizer. Nested ObservableObjects do not propagate on
        // their own, so those would only refresh when something else happened
        // to redraw the view.
        for child in [
            media.objectWillChange,
            shelf.objectWillChange,
            clipboard.objectWillChange,
            calendar.objectWillChange,
        ] {
            child
                .sink { [weak self] _ in self?.objectWillChange.send() }
                .store(in: &cancellables)
        }
    }

    /// Size of the visible body for the current state.
    var bodySize: CGSize {
        isOpen || isDropTargeted ? geometry.expandedSize : geometry.notchSize
    }

    /// Off switch for people who copy images all day and do not want them kept.
    static let saveClipboardImagesKey = "saveClipboardImages"

    func start() {
        media.start()
        shelf.load()
        // Only picks up where it left off if access was granted earlier; it
        // never prompts on its own.
        calendar.start()

        clipboard.onImage = { [weak self] png in
            guard let self else { return }
            let defaults = UserDefaults.standard
            guard defaults.object(forKey: Self.saveClipboardImagesKey) == nil
                    || defaults.bool(forKey: Self.saveClipboardImagesKey) else { return }
            guard let url = ScreenshotVault.save(png) else { return }
            self.shelf.add([url])
            self.tab = .shelf
        }
        clipboard.start()
    }

    func stop() {
        media.stop()
        clipboard.stop()
        calendar.stop()
    }

    func accept(urls: [URL]) -> Bool {
        shelf.add(urls)
        tab = .shelf
        return true
    }
}
