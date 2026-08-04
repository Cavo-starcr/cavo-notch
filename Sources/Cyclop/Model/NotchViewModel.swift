import AppKit
import Combine

@MainActor
final class NotchViewModel: ObservableObject {
    enum Tab: String, CaseIterable, Identifiable {
        case media, shelf, clipboard
        var id: String { rawValue }

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
    @Published var tab: Tab = .media
    @Published var isDropTargeted = false

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
