import AppKit

/// Zips shelf cards.
///
/// `ditto` rather than an in-process archiver: it is the tool the system itself
/// uses, it carries resource forks and Finder metadata across correctly, and it
/// handles a bundle (an .app, a .rtfd, a Logic project) as the folder it really
/// is. A hand-rolled zip would either lose that or grow into a library this app
/// has no business shipping. Same call the Now Playing feed already makes, so
/// the app gains no new kind of dependency, only one more platform binary.
enum Archiver {
    /// Where archives land.
    ///
    /// Downloads, not next to the originals: shelf cards come from anywhere at
    /// all — including the screenshots folder this app owns and a read-only
    /// volume — and "next to" is a location the person cannot predict before
    /// pressing the button. Downloads is writable, expected, and already where
    /// the rest of the day's loose files are.
    private static var destination: URL {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
    }

    /// Compresses `urls` into one archive and returns it.
    ///
    /// One file keeps its own name; several go into `Archive.zip`, and the items
    /// sit at the top level of it rather than inside a wrapper folder — which is
    /// what Finder's own Compress does with a multiple selection.
    static func zip(_ urls: [URL]) async -> URL? {
        let existing = urls.filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !existing.isEmpty else { return nil }

        let name = existing.count == 1
            ? existing[0].deletingPathExtension().lastPathComponent
            : localized("Archive")
        let output = uniqueURL(name: name)

        do {
            if existing.count == 1 {
                // `--keepParent` names what the archive holds, and the two kinds
                // of source need opposite answers. On a folder it keeps the
                // folder itself, so unzipping gives `folder/…` rather than the
                // contents strewn across wherever it was opened. On a *file* it
                // keeps the containing directory instead — `-c --keepParent
                // ~/Desktop/a.txt` produces an archive of `Desktop/a.txt` — so a
                // plain file must go without it. Verified against ditto rather
                // than assumed: this is the one flag here whose meaning is not
                // what its name suggests.
                var arguments = ["-c", "-k", "--sequesterRsrc"]
                if isDirectory(existing[0]) { arguments.append("--keepParent") }
                arguments += [existing[0].path, output.path]
                try await run(arguments)
            } else {
                // Everything is gathered into one staging folder first, and that
                // folder's *contents* are zipped — that is the only way ditto
                // produces a flat archive of several items.
                let staging = FileManager.default.temporaryDirectory
                    .appendingPathComponent("cyclop-zip-\(UUID().uuidString)", isDirectory: true)
                try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
                defer { try? FileManager.default.removeItem(at: staging) }

                for url in existing {
                    let link = staging.appendingPathComponent(uniqueName(for: url, in: staging))
                    // Hard-linked, not copied: instant and free whatever the file
                    // weighs. Across volumes there is no such link, so those fall
                    // back to a copy — the only case where a big file is read.
                    do {
                        try FileManager.default.linkItem(at: url, to: link)
                    } catch {
                        try FileManager.default.copyItem(at: url, to: link)
                    }
                }
                try await run(["-c", "-k", "--sequesterRsrc", staging.path, output.path])
            }
        } catch {
            NSLog("Cyclop: zip failed: \(error.localizedDescription)")
            return nil
        }

        guard FileManager.default.fileExists(atPath: output.path) else { return nil }
        return output
    }

    /// A real directory, and not a bundle.
    ///
    /// A bundle — an .app, an .rtfd, a Logic project — is a directory on disk and
    /// a single document to everyone looking at it, and it needs the folder-shaped
    /// treatment: zipping its contents flat is how an .app arrives as a heap of
    /// `Contents/` and stops being an app.
    private static func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
    }

    /// `Archive.zip`, `Archive 2.zip`, … — never overwriting whatever is already
    /// in Downloads under that name.
    private static func uniqueURL(name: String) -> URL {
        let folder = destination
        var candidate = folder.appendingPathComponent("\(name).zip")
        var counter = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = folder.appendingPathComponent("\(name) \(counter).zip")
            counter += 1
        }
        return candidate
    }

    /// Two shelf cards can be two different files with the same name — one from
    /// Desktop and one from Downloads. Inside the staging folder the second
    /// would overwrite the first, so it is renamed rather than lost.
    private static func uniqueName(for url: URL, in folder: URL) -> String {
        let base = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        var name = url.lastPathComponent
        var counter = 2
        while FileManager.default.fileExists(atPath: folder.appendingPathComponent(name).path) {
            name = ext.isEmpty ? "\(base) \(counter)" : "\(base) \(counter).\(ext)"
            counter += 1
        }
        return name
    }

    /// Runs ditto off the main thread and fails loudly on a non-zero exit.
    private static func run(_ arguments: [String]) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let task = Process()
                task.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
                task.arguments = arguments
                // stderr is captured rather than inherited: ditto is chatty about
                // extended attributes it cannot carry, and those lines would end
                // up in the system log as if the app had something to say.
                task.standardError = Pipe()
                task.standardOutput = Pipe()
                do {
                    try task.run()
                    task.waitUntilExit()
                    if task.terminationStatus == 0 {
                        continuation.resume()
                    } else {
                        continuation.resume(throwing: CocoaError(.fileWriteUnknown))
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
