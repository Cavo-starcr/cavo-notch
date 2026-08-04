import AppKit
import Combine

/// Aggregates Now Playing from whichever source is allowed to answer:
/// MediaRemote when the system still permits it, otherwise the scripting
/// bridge to Music/Spotify.
@MainActor
final class MediaController: ObservableObject {
    struct Track: Equatable {
        var title: String
        var artist: String
        var album: String
        var key: String
    }

    @Published private(set) var track: Track?
    @Published private(set) var artwork: NSImage?
    @Published private(set) var isPlaying = false
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var position: TimeInterval = 0
    @Published private(set) var sourceName: String?
    /// Set when a browser is playing but refuses JavaScript from Apple Events.
    @Published private(set) var setupHint: String?

    /// Set once MediaRemote is confirmed to actually return data on this system.
    private var mediaRemoteWorks = false
    private var activeApp: PlayerApp?
    private var activeBrowser: BrowserPlayback?
    private var pollTimer: Timer?
    private var artworkKey: String?
    private var anchor: (position: TimeInterval, at: Date)?
    private var ticker: Timer?
    private var observers: [Any] = []

    // MARK: - Lifecycle

    func start() {
        let center = DistributedNotificationCenter.default()
        for app in PlayerApp.allCases {
            observers.append(center.addObserver(
                forName: app.changeNotification, object: nil, queue: .main
            ) { [weak self] note in
                MainActor.assumeIsolated { self?.handle(note, from: app) }
            })
        }

        if MediaRemoteBridge.shared.isAvailable {
            for name in [MediaRemoteBridge.infoDidChange, MediaRemoteBridge.isPlayingDidChange] {
                observers.append(NotificationCenter.default.addObserver(
                    forName: name, object: nil, queue: .main
                ) { [weak self] _ in
                    MainActor.assumeIsolated { self?.refresh() }
                })
            }
        }

        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            observers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            })
        }

        refresh()
    }

    /// Browsers cannot notify us, so they are polled — but only while the
    /// panel is open, which is the only time the track is on screen.
    func setActive(_ active: Bool) {
        pollTimer?.invalidate()
        pollTimer = nil
        guard active else { return }
        refresh()
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    func stop() {
        observers.forEach {
            DistributedNotificationCenter.default().removeObserver($0)
            NotificationCenter.default.removeObserver($0)
            NSWorkspace.shared.notificationCenter.removeObserver($0)
        }
        observers.removeAll()
        ticker?.invalidate()
        ticker = nil
        pollTimer?.invalidate()
        pollTimer = nil
    }

    // MARK: - Transport

    func togglePlayPause() {
        // Optimistic flip so the button feels instant; the next state event corrects it.
        isPlaying.toggle()
        setAnchor(position)
        dispatch(script: { PlayerBridge.playPause($0) }, remote: .togglePlayPause, key: .playPause)
    }

    func next() {
        dispatch(script: { PlayerBridge.next($0) }, remote: .next, key: .next)
        refreshSoon()
    }

    func previous() {
        dispatch(script: { PlayerBridge.previous($0) }, remote: .previous, key: .previous)
        refreshSoon()
    }

    func seek(to seconds: TimeInterval) {
        guard duration > 0 else { return }
        let clamped = min(max(0, seconds), duration)
        position = clamped
        setAnchor(clamped)
        if let activeApp {
            PlayerBridge.seek(activeApp, to: clamped)
        } else if let activeBrowser {
            BrowserBridge.seek(activeBrowser, to: clamped)
        }
    }

    private func dispatch(
        script: (PlayerApp) -> Void,
        remote: MediaRemoteBridge.Command,
        key: PlayerBridge.MediaKey
    ) {
        if let activeApp {
            script(activeApp)
        } else if let activeBrowser, key == .playPause {
            BrowserBridge.playPause(activeBrowser)
            refreshSoon()
        } else if mediaRemoteWorks {
            MediaRemoteBridge.shared.send(remote)
        } else {
            // Nothing scriptable is playing — fall back to the system media key
            // so browsers and other players still respond.
            PlayerBridge.postMediaKey(key.rawValue)
        }
    }

    // MARK: - State

    private func handle(_ note: Notification, from app: PlayerApp) {
        // The payload is enough for title/artist/state; position and artwork
        // still need a round trip, so just re-read everything.
        _ = note
        activeApp = app
        refresh()
    }

    private func refreshSoon() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in self?.refresh() }
    }

    func refresh() {
        MediaRemoteBridge.shared.nowPlaying { [weak self] snapshot in
            guard let self else { return }
            if let snapshot, let title = snapshot.title {
                self.mediaRemoteWorks = true
                self.applyRemote(snapshot, title: title)
            } else {
                self.refreshFromPlayers()
            }
        }
    }

    private func applyRemote(_ snapshot: MediaRemoteBridge.Snapshot, title: String) {
        let new = Track(
            title: title,
            artist: snapshot.artist ?? "",
            album: snapshot.album ?? "",
            key: "mr|\(title)|\(snapshot.artist ?? "")"
        )
        track = new
        duration = snapshot.duration ?? 0
        setAnchor(snapshot.elapsed ?? 0)
        sourceName = sourceName ?? "Система"
        if artworkKey != new.key {
            artworkKey = new.key
            artwork = snapshot.artwork.flatMap(NSImage.init(data:))
        }
        MediaRemoteBridge.shared.isPlaying { [weak self] playing in
            self?.isPlaying = playing
            self?.updateTicker()
        }
    }

    private func refreshFromPlayers() {
        PlayerBridge.currentState { [weak self] state in
            guard let self else { return }
            // A playing app wins outright; otherwise look in the browser before
            // settling for a player that is merely paused.
            if let state, state.isPlaying { return self.apply(state) }
            BrowserBridge.currentPlayback { [weak self] browser in
                guard let self else { return }
                self.setupHint = BrowserBridge.setupHint
                if let browser { return self.apply(browser) }
                if let state { return self.apply(state) }
                self.clear()
            }
        }
    }

    private func clear() {
        activeApp = nil
        activeBrowser = nil
        track = nil
        artwork = nil
        artworkKey = nil
        isPlaying = false
        duration = 0
        position = 0
        sourceName = nil
        updateTicker()
    }

    private func apply(_ browser: BrowserPlayback) {
        activeApp = nil
        activeBrowser = browser
        sourceName = browser.browser.displayName
        track = Track(title: browser.title, artist: browser.artist, album: browser.album, key: browser.key)
        isPlaying = browser.isPlaying
        duration = browser.duration
        setAnchor(browser.position)
        updateTicker()

        guard artworkKey != browser.key else { return }
        artworkKey = browser.key
        artwork = nil
        guard let url = browser.artworkURL else { return }
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            let image = data.flatMap(NSImage.init(data:))
            DispatchQueue.main.async {
                guard let self, self.artworkKey == browser.key else { return }
                self.artwork = image
            }
        }.resume()
    }

    private func apply(_ state: PlayerState) {
        activeBrowser = nil
        activeApp = state.app
        sourceName = state.app.displayName
        track = Track(title: state.title, artist: state.artist, album: state.album, key: state.key)
        isPlaying = state.isPlaying
        duration = state.duration
        setAnchor(state.position)
        updateTicker()

        guard artworkKey != state.key else { return }
        artworkKey = state.key
        artwork = nil
        PlayerBridge.artwork(for: state) { [weak self] image in
            guard let self, self.artworkKey == state.key else { return }
            self.artwork = image
        }
    }

    // MARK: - Position

    private func setAnchor(_ value: TimeInterval) {
        position = value
        anchor = (value, Date())
    }

    private func updateTicker() {
        ticker?.invalidate()
        ticker = nil
        guard isPlaying else { return }
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    private func tick() {
        guard let anchor, isPlaying else { return }
        let value = anchor.position + Date().timeIntervalSince(anchor.at)
        position = duration > 0 ? min(value, duration) : value
        // Roll over to the next track shortly after the current one ends.
        if duration > 0, value >= duration + 0.5 { refresh() }
    }
}
