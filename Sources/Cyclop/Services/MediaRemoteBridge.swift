import Foundation

/// Thin `dlopen` wrapper around the private MediaRemote framework.
///
/// macOS 15.4 gated `MRMediaRemoteGetNowPlayingInfo` behind the private
/// `com.apple.mediaremote.external-access` entitlement, so on current systems
/// this yields nothing and `MediaController` falls back to the scripting
/// bridge. It stays in the build because it costs one `dlopen` and gives full,
/// app-agnostic Now Playing (browsers included) wherever it is still allowed.
final class MediaRemoteBridge {
    struct Snapshot {
        var title: String?
        var artist: String?
        var album: String?
        var artwork: Data?
        var duration: TimeInterval?
        var elapsed: TimeInterval?
    }

    static let shared = MediaRemoteBridge()

    private typealias GetInfoFn = @convention(c) (DispatchQueue, @escaping ([String: Any]) -> Void) -> Void
    private typealias GetIsPlayingFn = @convention(c) (DispatchQueue, @escaping (Bool) -> Void) -> Void
    private typealias RegisterFn = @convention(c) (DispatchQueue) -> Void
    private typealias SendCommandFn = @convention(c) (Int, [String: Any]?) -> Bool

    enum Command: Int {
        case play = 0, pause = 1, togglePlayPause = 2, next = 4, previous = 5
    }

    private var handle: UnsafeMutableRawPointer?
    private var getInfo: GetInfoFn?
    private var getIsPlaying: GetIsPlayingFn?
    private var sendCommand: SendCommandFn?

    let isAvailable: Bool

    private init() {
        let path = "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote"
        guard let handle = dlopen(path, RTLD_LAZY) else {
            isAvailable = false
            return
        }
        self.handle = handle

        func symbol<T>(_ name: String, as type: T.Type) -> T? {
            guard let sym = dlsym(handle, name) else { return nil }
            return unsafeBitCast(sym, to: type)
        }

        getInfo = symbol("MRMediaRemoteGetNowPlayingInfo", as: GetInfoFn.self)
        getIsPlaying = symbol("MRMediaRemoteGetNowPlayingApplicationIsPlaying", as: GetIsPlayingFn.self)
        sendCommand = symbol("MRMediaRemoteSendCommand", as: SendCommandFn.self)

        if let register = symbol("MRMediaRemoteRegisterForNowPlayingNotifications", as: RegisterFn.self) {
            register(.main)
        }
        isAvailable = getInfo != nil
    }

    /// Notification names posted once `MRMediaRemoteRegisterForNowPlayingNotifications` ran.
    static let infoDidChange = Notification.Name("kMRMediaRemoteNowPlayingInfoDidChangeNotification")
    static let isPlayingDidChange = Notification.Name("kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification")

    func nowPlaying(_ completion: @escaping (Snapshot?) -> Void) {
        guard let getInfo else { return completion(nil) }
        getInfo(.main) { info in
            guard !info.isEmpty else { return completion(nil) }
            let snapshot = Snapshot(
                title: info["kMRMediaRemoteNowPlayingInfoTitle"] as? String,
                artist: info["kMRMediaRemoteNowPlayingInfoArtist"] as? String,
                album: info["kMRMediaRemoteNowPlayingInfoAlbum"] as? String,
                artwork: info["kMRMediaRemoteNowPlayingInfoArtworkData"] as? Data,
                duration: info["kMRMediaRemoteNowPlayingInfoDuration"] as? TimeInterval,
                elapsed: info["kMRMediaRemoteNowPlayingInfoElapsedTime"] as? TimeInterval
            )
            completion(snapshot.title == nil ? nil : snapshot)
        }
    }

    func isPlaying(_ completion: @escaping (Bool) -> Void) {
        guard let getIsPlaying else { return completion(false) }
        getIsPlaying(.main) { completion($0) }
    }

    @discardableResult
    func send(_ command: Command) -> Bool {
        sendCommand?(command.rawValue, nil) ?? false
    }
}
