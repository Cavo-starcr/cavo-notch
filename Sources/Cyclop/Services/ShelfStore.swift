import AppKit

struct ShelfItem: Identifiable, Equatable {
    let id = UUID()
    let url: URL
    let icon: NSImage
    var name: String { url.lastPathComponent }

    static func == (lhs: ShelfItem, rhs: ShelfItem) -> Bool { lhs.url == rhs.url }
}

/// Drop zone contents. Files are referenced, never copied — the shelf is a
/// holding area, so moving the original away simply removes it from the shelf.
@MainActor
final class ShelfStore: ObservableObject {
    @Published private(set) var items: [ShelfItem] = []

    private let defaultsKey = "shelf.urls"
    private let limit = 24

    func load() {
        let paths = UserDefaults.standard.stringArray(forKey: defaultsKey) ?? []
        items = paths
            .map(URL.init(fileURLWithPath:))
            .filter { FileManager.default.fileExists(atPath: $0.path) }
            .map { ShelfItem(url: $0, icon: NSWorkspace.shared.icon(forFile: $0.path)) }
    }

    func add(_ urls: [URL]) {
        for url in urls where !items.contains(where: { $0.url == url }) {
            items.insert(ShelfItem(url: url, icon: NSWorkspace.shared.icon(forFile: url.path)), at: 0)
        }
        if items.count > limit { items.removeLast(items.count - limit) }
        persist()
    }

    func remove(_ item: ShelfItem) {
        items.removeAll { $0.id == item.id }
        persist()
    }

    func clear() {
        items.removeAll()
        persist()
    }

    func reveal(_ item: ShelfItem) {
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }

    func open(_ item: ShelfItem) {
        NSWorkspace.shared.open(item.url)
    }

    private func persist() {
        UserDefaults.standard.set(items.map(\.url.path), forKey: defaultsKey)
    }
}
