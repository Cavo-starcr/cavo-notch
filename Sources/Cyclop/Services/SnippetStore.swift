import AppKit

struct Snippet: Identifiable, Codable, Equatable {
    var id: String { label.isEmpty ? text : label }
    /// Optional name. Without one the row shows the value itself, which is
    /// usually enough for an address or a phone number.
    var label: String = ""
    var text: String

    /// Guessed from the value, so a row is recognisable before it is read.
    var symbol: String {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.contains("@"), !value.contains(" ") { return "at" }
        if value.hasPrefix("http://") || value.hasPrefix("https://") { return "link" }
        let digits = value.filter(\.isNumber).count
        if digits >= 7, value.allSatisfy({ $0.isNumber || " +-()".contains($0) }) { return "phone.fill" }
        return "text.alignleft"
    }
}

/// A hand-kept list of things worth not retyping.
///
/// Read from a file and never written to. It is deliberately not fed by the
/// clipboard: the clipboard is a queue ordered by recency, which loses exactly
/// the entry used once a month, and anything automatic would fill this with
/// whatever happened to pass through. What belongs here is decided by hand,
/// and the file is where that decision lives.
@MainActor
final class SnippetStore: ObservableObject {
    @Published private(set) var items: [Snippet] = []
    @Published var query = ""

    /// Matches the name and the value alike: one remembers an address either by
    /// what it is called or by what is in it, rarely reliably by both.
    var filtered: [Snippet] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return items }
        return items.filter { $0.label.matches(needle) || $0.text.matches(needle) }
    }

    /// `~/Library/Application Support/Cyclop/snippets.json`. A plain array of
    /// `{"label": "...", "text": "..."}`, where `label` may be left out.
    static let file: URL = {
        let fm = FileManager.default
        let folder = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Cyclop", isDirectory: true)
        try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("snippets.json")
    }()

    /// Re-read on every visit to the tab. The file is edited from outside the
    /// app, so the only sensible moment to trust what is in memory is the
    /// moment before it is shown.
    func reload() {
        guard let data = try? Data(contentsOf: Self.file) else {
            items = []
            return
        }
        do {
            items = try JSONDecoder().decode([Snippet].self, from: data)
        } catch {
            NSLog("Cyclop: snippets.json is not readable: \(error.localizedDescription)")
        }
    }

    /// Puts a snippet on the pasteboard, ready to paste.
    ///
    /// The pasteboard is the only way to hand text to another app without
    /// asking for Accessibility, which this app is built not to do. Whatever
    /// was there is overwritten, and stays available in the clipboard tab.
    func copy(_ snippet: Snippet) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(snippet.text, forType: .string)
    }

    static func reveal() {
        NSWorkspace.shared.activateFileViewerSelecting([file])
    }
}

private extension String {
    /// Case- and accent-blind, so "почта" finds "Почта" and "Nagy" finds "Nagy".
    func matches(_ needle: String) -> Bool {
        range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }
}
