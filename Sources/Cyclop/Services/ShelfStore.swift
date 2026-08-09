import AppKit
import QuickLookThumbnailing
import UniformTypeIdentifiers

extension NSPasteboard.PasteboardType {
    /// Marker Cyclop puts on pasteboard writes of its own.
    static let cyclopInternal = NSPasteboard.PasteboardType("com.cyclop.internal")
}

struct ShelfItem: Identifiable, Equatable {
    let id = UUID()
    let url: URL
    /// Starts as the file-type icon and is replaced by a real preview once
    /// QuickLook renders one — a shelf of identical PNG icons is useless when
    /// what it holds is screenshots.
    var icon: NSImage
    var name: String { url.lastPathComponent }

    static func == (lhs: ShelfItem, rhs: ShelfItem) -> Bool { lhs.url == rhs.url }
}

/// Drop zone contents. Files are referenced, never copied — the shelf is a
/// holding area, so moving the original away simply removes it from the shelf.
@MainActor
final class ShelfStore: ObservableObject {
    @Published private(set) var items: [ShelfItem] = []
    /// Cards picked for a group drag. Empty means "drag whatever is grabbed".
    @Published private(set) var selection: Set<UUID> = []
    /// True while ditto is running. Zipping a folder of raw photographs takes
    /// long enough that a button which looks idle invites a second press, and
    /// the second press would build a second archive.
    @Published private(set) var isCompressing = false

    /// The card under the pointer, handed up by the pane — which is the only
    /// place that can work it out correctly (see `ShelfPane`).
    ///
    /// Emphatically *not* `@Published`: this changes with every pointer movement
    /// across the strip, and the view model forwards this store's changes to the
    /// whole panel, so publishing it would re-render everything on mouse-move —
    /// the exact stutter the pane's own hover machinery exists to avoid. Nothing
    /// draws from it; it is read once, when a key is pressed.
    var hoveredID: UUID?

    private let defaultsKey = "shelf.urls"
    /// Generous, because saved screenshots accumulate here and nothing is
    /// deleted behind the user's back. Cards past the limit leave the shelf,
    /// but their files stay in the folder.
    private let limit = 60

    func load() {
        // Card ids are minted per instance, so a reload orphans any selection:
        // the ids it holds now name nothing. Kept, they showed as a phantom
        // "Selected: N" in the footer with no card marked (#10).
        selection.removeAll()
        let paths = UserDefaults.standard.stringArray(forKey: defaultsKey) ?? []
        items = paths
            .map(URL.init(fileURLWithPath:))
            .filter { FileManager.default.fileExists(atPath: $0.path) }
            .map { ShelfItem(url: $0, icon: NSWorkspace.shared.icon(forFile: $0.path)) }
        items.forEach(loadThumbnail)
    }

    func add(_ urls: [URL]) {
        for url in urls where !items.contains(where: { $0.url == url }) {
            let item = ShelfItem(url: url, icon: NSWorkspace.shared.icon(forFile: url.path))
            items.insert(item, at: 0)
            loadThumbnail(item)
        }
        if items.count > limit { items.removeLast(items.count - limit) }
        persist()
    }

    private func loadThumbnail(_ item: ShelfItem) {
        // A square box QuickLook fits the content into, whatever its shape.
        // Generous enough that a landscape screenshot still lands above the
        // card's pixel size once it has been fitted.
        let request = QLThumbnailGenerator.Request(
            fileAt: item.url,
            size: CGSize(width: 96, height: 96),
            scale: 2,
            representationTypes: .thumbnail
        )
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { [weak self] rep, _ in
            guard let rep else { return }
            // `nsImage` already carries the right point size for the
            // representation; deriving one from `contentRect` risks describing
            // a shape the bitmap does not have.
            let image = rep.nsImage
            Task { @MainActor in
                guard let self, let index = self.items.firstIndex(where: { $0.url == item.url }) else { return }
                self.items[index].icon = image
            }
        }
    }

    func remove(_ item: ShelfItem) {
        items.removeAll { $0.id == item.id }
        selection.remove(item.id)
        persist()
    }

    func clear() {
        items.removeAll()
        selection.removeAll()
        persist()
    }

    // MARK: - Selection

    /// Plain click replaces the selection; ⌘ or ⇧ adds to it, matching Finder.
    func select(_ item: ShelfItem, modifiers: NSEvent.ModifierFlags) {
        if modifiers.contains(.command) || modifiers.contains(.shift) {
            if selection.contains(item.id) {
                selection.remove(item.id)
            } else {
                selection.insert(item.id)
            }
        } else if selection == [item.id] {
            selection.removeAll()
        } else {
            selection = [item.id]
        }
    }

    func isSelected(_ item: ShelfItem) -> Bool { selection.contains(item.id) }

    func clearSelection() { selection.removeAll() }

    /// Files a drag started on `item` should carry: the whole selection when
    /// the grabbed card belongs to it, otherwise just that card.
    func dragURLs(startingAt item: ShelfItem) -> [URL] {
        guard selection.contains(item.id) else { return [item.url] }
        return items.filter { selection.contains($0.id) }.map(\.url)
    }

    func reveal(_ item: ShelfItem) {
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }

    /// Puts the card back on the pasteboard. Images go as image data as well as
    /// a file reference, so pasting works both in Finder and in an editor.
    func copy(_ item: ShelfItem) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        // The file goes on first and everything below is added to the item it
        // creates. Order is the whole of it: `setData` always writes to the
        // first item, `writeObjects` appends a new one — so marking first put
        // the picture on one item and the file on another. One card then
        // arrives as two objects, and an editor that accepts both pastes the
        // screenshot twice.
        pasteboard.writeObjects([item.url as NSURL])
        // Tells ClipboardStore this change came from us, so a copied screenshot
        // is not saved to disk a second time.
        pasteboard.setData(Data(), forType: .cyclopInternal)
        if let type = UTType(filenameExtension: item.url.pathExtension),
           type.conforms(to: .image),
           let data = try? Data(contentsOf: item.url) {
            // Declared as what the bytes are, not renamed to TIFF: consumers
            // that trust the declared type would save a "TIFF" with JPEG
            // inside (#9). The UTI is already the pasteboard type identifier.
            pasteboard.setData(data, forType: NSPasteboard.PasteboardType(type.identifier))
        }
    }

    func open(_ item: ShelfItem) {
        NSWorkspace.shared.open(item.url)
    }

    // MARK: - Card actions

    /// The files an action started on `item` should apply to — the same rule the
    /// drag uses, so the context menu and the drag never disagree about what
    /// "this card" means when several are selected.
    func actionURLs(startingAt item: ShelfItem) -> [URL] { dragURLs(startingAt: item) }

    /// The path as text, which is what a terminal, a config file or a colleague
    /// asks for. POSIX form, unescaped: quoting is the shell's business, and a
    /// path pasted into a text field should not arrive full of backslashes.
    func copyPath(_ item: ShelfItem) {
        let paths = actionURLs(startingAt: item).map(\.path).joined(separator: "\n")
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(paths, forType: .string)
        pasteboard.setData(Data(), forType: .cyclopInternal)
    }

    /// Quick Look, on the selection when the card belongs to one.
    func preview(_ item: ShelfItem) {
        QuickLook.shared.toggle(actionURLs(startingAt: item), starting: item.url)
    }

    /// What the space bar previews.
    ///
    /// The card under the pointer wins, because that is the one being looked at.
    /// Failing that the selection, and failing that the whole shelf from the
    /// front — Finder would do nothing here, but a shelf one can page through
    /// with the arrow keys is worth more than the purity.
    func previewFromKeyboard() {
        if let hoveredID, let item = items.first(where: { $0.id == hoveredID }) {
            preview(item)
            return
        }
        if let item = items.first(where: { selection.contains($0.id) }) {
            preview(item)
            return
        }
        guard let first = items.first else { return }
        QuickLook.shared.toggle(items.map(\.url), starting: first.url)
    }

    /// Hands the files to the system share sheet — AirDrop, Mail, Messages,
    /// whatever the person has. `NSSharingServicePicker` is the whole feature:
    /// it needs no permission and no knowledge of what it is sharing with.
    ///
    /// Anchored to a rect in the panel, so the popover points at the card
    /// instead of appearing at the corner of the screen.
    func share(_ item: ShelfItem, from view: NSView?, rect: NSRect) {
        let urls = actionURLs(startingAt: item)
        guard !urls.isEmpty, let view else { return }
        let picker = NSSharingServicePicker(items: urls)
        picker.show(relativeTo: rect, of: view, preferredEdge: .minY)
    }

    /// Zips the card (or the selection) and puts the archive on the shelf.
    ///
    /// The new card *is* the confirmation: the archive appears where the files
    /// came from, so there is nothing to read and dismiss. Where the file itself
    /// landed is `Archiver`'s business — Downloads, and it says why.
    func compress(_ item: ShelfItem) {
        let urls = actionURLs(startingAt: item)
        guard !urls.isEmpty else { return }
        isCompressing = true
        Task { [weak self] in
            let archive = await Archiver.zip(urls)
            guard let self else { return }
            self.isCompressing = false
            guard let archive else { return }
            self.add([archive])
            // The selection named the files that went in, and holding it after
            // the fact means the next action silently reaches for them again —
            // including another zip of the same set.
            self.clearSelection()
        }
    }

    /// Renames the file on disk and follows it on the shelf.
    ///
    /// Refuses anything with a path separator in it: this is a rename, and a
    /// name carrying a slash is a move, quietly, to somewhere nobody named.
    @discardableResult
    func rename(_ item: ShelfItem, to newName: String) -> Bool {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("/"), !trimmed.hasPrefix(".") else { return false }
        guard trimmed != item.name else { return true }
        let destination = item.url.deletingLastPathComponent().appendingPathComponent(trimmed)
        guard !FileManager.default.fileExists(atPath: destination.path) else { return false }
        do {
            try FileManager.default.moveItem(at: item.url, to: destination)
        } catch {
            NSLog("Cyclop: rename failed: \(error.localizedDescription)")
            return false
        }
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return true }
        // A card is identified by its URL, so the row is replaced rather than
        // edited — and the thumbnail is re-requested, because QuickLook caches
        // by URL and the old one now names nothing.
        let moved = ShelfItem(url: destination, icon: items[index].icon)
        items[index] = moved
        // Ids are minted per card, so the replacement carries a new one and the
        // selection would go on naming the card that no longer exists — the
        // phantom "Selected: N" with nothing marked, same as #10. Renaming a
        // picked card should leave it picked.
        if selection.remove(item.id) != nil { selection.insert(moved.id) }
        persist()
        loadThumbnail(moved)
        return true
    }

    private func persist() {
        UserDefaults.standard.set(items.map(\.url.path), forKey: defaultsKey)
    }
}
