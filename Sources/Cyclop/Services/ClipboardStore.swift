import AppKit

struct ClipItem: Identifiable, Equatable {
    enum Payload: Equatable {
        case text(String)
        case file(URL)
    }

    let id = UUID()
    let payload: Payload
    let date: Date

    var preview: String {
        switch payload {
        case .text(let string):
            return string.trimmingCharacters(in: .whitespacesAndNewlines)
        case .file(let url):
            return url.lastPathComponent
        }
    }

    var symbol: String {
        switch payload {
        case .text(let string):
            if string.hasPrefix("http://") || string.hasPrefix("https://") { return "link" }
            return "text.alignleft"
        case .file:
            return "doc"
        }
    }

    static func == (lhs: ClipItem, rhs: ClipItem) -> Bool { lhs.payload == rhs.payload }
}

/// Polls the general pasteboard's change counter. Cheap: one integer read
/// twice a second, and nothing at all is read until the counter moves.
@MainActor
final class ClipboardStore: ObservableObject {
    @Published private(set) var items: [ClipItem] = []

    /// Raised for image data on the pasteboard — a screenshot taken straight to
    /// the clipboard, which would otherwise vanish after one paste.
    var onImage: ((Data) -> Void)?

    private var timer: Timer?
    private var lastChangeCount = NSPasteboard.general.changeCount
    private let limit = 40
    /// Pasteboard type password managers set to opt out of history tools.
    private let concealed = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")

    func start() {
        stop()
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func clear() {
        items.removeAll()
    }

    func remove(_ item: ClipItem) {
        items.removeAll { $0.id == item.id }
    }

    /// Puts an entry back on the pasteboard without re-recording it.
    func copy(_ item: ClipItem) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        switch item.payload {
        case .text(let string):
            pasteboard.setString(string, forType: .string)
        case .file(let url):
            pasteboard.writeObjects([url as NSURL])
        }
        lastChangeCount = pasteboard.changeCount
        // Freshly used entries bubble to the top.
        if let index = items.firstIndex(where: { $0.id == item.id }), index != 0 {
            items.remove(at: index)
            items.insert(item, at: 0)
        }
    }

    private func poll() {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount

        guard pasteboard.data(forType: concealed) == nil else { return }

        // A copied file arrives as a URL, not as image data, so URLs win first.
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL],
           let url = urls.first {
            record(ClipItem(payload: .file(url), date: Date()))
            return
        }

        if let png = pngFromPasteboard(pasteboard) {
            onImage?(png)
            return
        }

        guard let string = pasteboard.string(forType: .string),
              !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        record(ClipItem(payload: .text(string), date: Date()))
    }

    /// Screenshots land as PNG; other apps often offer only TIFF.
    private func pngFromPasteboard(_ pasteboard: NSPasteboard) -> Data? {
        if let png = pasteboard.data(forType: .png) { return png }
        guard let tiff = pasteboard.data(forType: .tiff),
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    private func record(_ item: ClipItem) {
        items.removeAll { $0 == item }
        items.insert(item, at: 0)
        if items.count > limit { items.removeLast(items.count - limit) }
    }
}
