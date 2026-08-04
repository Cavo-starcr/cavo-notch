import AppKit
import Combine

@MainActor
final class NotchViewModel: ObservableObject {
    enum Tab: String, CaseIterable, Identifiable {
        case media, shelf, clipboard
        var id: String { rawValue }

        var order: Int { Self.allCases.firstIndex(of: self) ?? 0 }

        var symbol: String {
            switch self {
            case .media: return "music.note"
            case .shelf: return "tray.full.fill"
            case .clipboard: return "list.clipboard.fill"
            }
        }

        var title: String {
            switch self {
            case .media: return "Музыка"
            case .shelf: return "Полка"
            case .clipboard: return "Буфер"
            }
        }
    }

    @Published var isOpen = false
    @Published var isDropTargeted = false
    @Published var tab: Tab = .media {
        didSet { slidesForward = tab.order >= oldValue.order }
    }
    /// Direction the pane transition should travel, so tabs slide the way the
    /// eye expects rather than always from the same side.
    private(set) var slidesForward = true

    let geometry: NotchGeometry
    let media: MediaController
    let shelf: ShelfStore
    let clipboard: ClipboardStore

    init(geometry: NotchGeometry) {
        self.geometry = geometry
        self.media = MediaController()
        self.shelf = ShelfStore()
        self.clipboard = ClipboardStore()
    }

    /// Size of the visible body for the current state.
    var bodySize: CGSize {
        isOpen || isDropTargeted ? geometry.expandedSize : geometry.notchSize
    }

    func start() {
        media.start()
        clipboard.start()
        shelf.load()
    }

    func stop() {
        media.stop()
        clipboard.stop()
    }

    func accept(urls: [URL]) -> Bool {
        shelf.add(urls)
        tab = .shelf
        return true
    }
}
