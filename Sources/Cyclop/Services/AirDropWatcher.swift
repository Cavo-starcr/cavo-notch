import AppKit
import UniformTypeIdentifiers

/// Catches pictures AirDropped from a phone and hands them to the shelf.
///
/// Nothing announces an AirDrop. iOS will not talk to third-party code at all,
/// and on this side the whole transfer belongs to `sharingd`, which does one
/// observable thing: it puts the file in Downloads. So that is what is watched.
/// AirDrop between devices on one Apple ID is accepted without asking, so a
/// screenshot is on the Mac about a second after the share sheet is tapped —
/// no iCloud, no sync to wait for, and it works with no internet at all.
@MainActor
final class AirDropWatcher {
    /// Files that just arrived, in the order they were found.
    var onArrival: (([URL]) -> Void)?

    /// Off switch. On by default — the folder is only ever read, and only for
    /// things that appear while the app is running.
    static let enabledKey = "catchAirDrops"

    static var isEnabled: Bool {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: enabledKey) != nil else { return true }
        return defaults.bool(forKey: enabledKey)
    }

    private let folder = FileManager.default
        .urls(for: .downloadsDirectory, in: .userDomainMask)[0]

    private var source: DispatchSourceFileSystemObject?
    private var descriptor: CInt = -1
    private var settle: DispatchWorkItem?

    /// Everything already in the folder when watching began. Only arrivals are
    /// interesting; the downloads of the last three months are not.
    private var known: Set<String> = []

    /// How fresh a file has to be to count as an arrival. Guards the case where
    /// the folder changes for an unrelated reason and an old file shows up in
    /// the listing as new — a rename, say.
    private let freshness: TimeInterval = 90

    // MARK: - Lifecycle

    func start() {
        guard Self.isEnabled, source == nil else { return }
        // Reading the listing is what raises the Downloads permission prompt, if
        // it has not been answered yet. Nothing else here touches the folder.
        known = Set(contents().map(\.lastPathComponent))

        descriptor = open(folder.path, O_EVTONLY)
        guard descriptor >= 0 else {
            NSLog("Cyclop: cannot watch \(folder.path)")
            return
        }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: .write,
            queue: .main
        )
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.folderChanged() }
        }
        source.setCancelHandler { [descriptor] in
            if descriptor >= 0 { close(descriptor) }
        }
        source.resume()
        self.source = source
    }

    func stop() {
        settle?.cancel()
        settle = nil
        source?.cancel()
        source = nil
        descriptor = -1
        known.removeAll()
    }

    // MARK: - Watching

    /// A directory write fires once per change, and one arriving file makes
    /// several — created, written, renamed into place. Waiting out the burst
    /// means the file is whole by the time it is looked at.
    private func folderChanged() {
        settle?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.collect() }
        }
        settle = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    private func collect() {
        let now = Date()
        var arrived: [URL] = []

        for url in contents() {
            let name = url.lastPathComponent
            guard !known.contains(name) else { continue }
            known.insert(name)

            let values = try? url.resourceValues(forKeys: [
                .contentTypeKey, .contentModificationDateKey, .isRegularFileKey,
            ])
            guard values?.isRegularFile == true,
                  values?.contentType?.conforms(to: .image) == true,
                  let modified = values?.contentModificationDate,
                  now.timeIntervalSince(modified) < freshness,
                  camePeerToPeer(url)
            else { continue }

            arrived.append(url)
        }

        guard !arrived.isEmpty else { return }
        onArrival?(arrived)
    }

    /// Where the file came from, read off its quarantine stamp. macOS records
    /// the app responsible for every arrival: Safari signs its downloads
    /// "Safari", Telegram signs its own, and AirDrop — handled by `sharingd` —
    /// signs "Sharing". A file with no stamp at all was put there by something
    /// that is not a download agent, which is the one other case worth taking:
    /// it is what a file saved straight into the folder looks like.
    private func camePeerToPeer(_ url: URL) -> Bool {
        let values = try? url.resourceValues(forKeys: [.quarantinePropertiesKey])
        guard let quarantine = values?.quarantineProperties else { return true }
        let agent = quarantine[kLSQuarantineAgentNameKey as String] as? String ?? ""
        let peer = agent.localizedCaseInsensitiveContains("sharing")
            || agent.localizedCaseInsensitiveContains("airdrop")
        // Named, because the whole rule rests on what macOS writes here and the
        // only way to see it is to have looked. A picture that should have
        // landed on the shelf and did not says why on its way past.
        if !peer { NSLog("Cyclop: ignoring \(url.lastPathComponent), delivered by \(agent)") }
        return peer
    }

    private func contents() -> [URL] {
        (try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.contentTypeKey, .contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
        )) ?? []
    }
}
