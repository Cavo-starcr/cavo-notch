import AppKit

/// Where clipboard screenshots are kept.
///
/// A screenshot taken to the clipboard exists only in memory: paste it once and
/// it is gone. The vault writes it to disk so the shelf can hold on to it.
/// Nothing here is ever deleted automatically — the folder is the user's.
enum ScreenshotVault {
    /// `~/Pictures/Cyclop` when it can be created — it is findable, and unlike
    /// Desktop or Documents it is not behind a TCC prompt. Falls back to the
    /// app's own support folder, which always works.
    static let folder: URL = {
        let fm = FileManager.default
        let pictures = fm.homeDirectoryForCurrentUser
            .appendingPathComponent("Pictures", isDirectory: true)
            .appendingPathComponent("Cyclop", isDirectory: true)
        if (try? fm.createDirectory(at: pictures, withIntermediateDirectories: true)) != nil {
            return pictures
        }
        let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Cyclop", isDirectory: true)
            .appendingPathComponent("Screenshots", isDirectory: true)
        try? fm.createDirectory(at: support, withIntermediateDirectories: true)
        return support
    }()

    private static let stamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd 'в' HH.mm.ss"
        return formatter
    }()

    static func save(_ png: Data, at date: Date = Date()) -> URL? {
        var url = folder.appendingPathComponent("Снимок \(stamp.string(from: date)).png")
        // Two screenshots inside one second would otherwise collide.
        var attempt = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = folder.appendingPathComponent("Снимок \(stamp.string(from: date)) (\(attempt)).png")
            attempt += 1
        }
        do {
            try png.write(to: url, options: .atomic)
            return url
        } catch {
            NSLog("Cyclop: failed to save clipboard image: \(error.localizedDescription)")
            return nil
        }
    }

    static func reveal() {
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: folder.path)
    }
}
