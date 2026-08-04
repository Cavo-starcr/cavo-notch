import AppKit

/// Reads Now Playing out of a browser tab via `navigator.mediaSession`.
///
/// Browsers publish their metadata to the system only through MediaRemote,
/// which macOS 15.4 closed off. The Media Session API carries exactly the same
/// data — title, artist, album, artwork — and is reachable with AppleScript's
/// JavaScript execution, so this is the one public route to a browser's track.
enum BrowserApp: String, CaseIterable {
    case chrome, brave, edge, arc, safari

    var bundleID: String {
        switch self {
        case .chrome: return "com.google.Chrome"
        case .brave: return "com.brave.Browser"
        case .edge: return "com.microsoft.edgemac"
        case .arc: return "company.thebrowser.Browser"
        case .safari: return "com.apple.Safari"
        }
    }

    var displayName: String {
        switch self {
        case .chrome: return "Chrome"
        case .brave: return "Brave"
        case .edge: return "Edge"
        case .arc: return "Arc"
        case .safari: return "Safari"
        }
    }

    /// Safari has its own JavaScript verb; everything else is Chromium.
    var isSafari: Bool { self == .safari }

    var isRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    /// Where the user turns on JavaScript execution from Apple Events.
    /// Menu names are given in English: these menus are rarely localized, and
    /// the English wording is what the setting is documented under.
    var setupHint: String {
        isSafari
            ? "Включи в Safari: Develop → Allow JavaScript from Apple Events"
            : "Включи в \(displayName): View → Developer → Allow JavaScript from Apple Events"
    }
}

struct BrowserPlayback {
    var browser: BrowserApp
    var isPlaying: Bool
    var title: String
    var artist: String
    var album: String
    var duration: TimeInterval
    var position: TimeInterval
    var artworkURL: URL?
    /// Tab coordinates, so the next poll can check the same tab first.
    var window: Int
    var tab: Int

    var key: String { "\(browser.rawValue)|\(title)|\(artist)" }
}

enum BrowserBridge {
    /// What the user has to turn on, if a browser refused to answer. The two
    /// refusals need different fixes: one is a Chrome/Safari menu toggle, the
    /// other is macOS Automation permission.
    private(set) static var setupHint: String?

    /// Tab that answered last time. Checked first so the common case costs one
    /// Apple Event instead of a sweep over every open tab.
    private static var lastHit: [BrowserApp: (window: Int, tab: Int)] = [:]
    private static var lastSweep: [BrowserApp: Date] = [:]
    private static let sweepInterval: TimeInterval = 5
    /// Upper bound on tabs visited per sweep, so a 100-tab window stays cheap.
    private static let tabBudget = 40

    // MARK: - Query

    static func currentPlayback(completion: @escaping (BrowserPlayback?) -> Void) {
        let running = BrowserApp.allCases.filter(\.isRunning)
        guard !running.isEmpty else {
            setupHint = nil
            return completion(nil)
        }
        query(running, index: 0, best: nil, completion: completion)
    }

    private static func query(
        _ browsers: [BrowserApp],
        index: Int,
        best: BrowserPlayback?,
        completion: @escaping (BrowserPlayback?) -> Void
    ) {
        guard index < browsers.count else { return completion(best) }
        playback(in: browsers[index]) { found in
            // A playing tab wins immediately; a paused one is only a fallback.
            if let found, found.isPlaying { return completion(found) }
            query(browsers, index: index + 1, best: best ?? found, completion: completion)
        }
    }

    private static func playback(in browser: BrowserApp, completion: @escaping (BrowserPlayback?) -> Void) {
        if let hit = lastHit[browser] {
            PlayerBridge.runScript(singleTabScript(browser, window: hit.window, tab: hit.tab)) { descriptor in
                if let state = parse(descriptor?.stringValue, browser: browser, window: hit.window, tab: hit.tab) {
                    return completion(state)
                }
                lastHit[browser] = nil
                sweep(browser, completion: completion)
            }
            return
        }
        sweep(browser, completion: completion)
    }

    private static func sweep(_ browser: BrowserApp, completion: @escaping (BrowserPlayback?) -> Void) {
        if let last = lastSweep[browser], Date().timeIntervalSince(last) < sweepInterval {
            return completion(nil)
        }
        lastSweep[browser] = Date()
        PlayerBridge.runScript(sweepScript(browser)) { descriptor in
            let parts = (descriptor?.stringValue ?? "").components(separatedBy: "\u{1}")
            guard parts.count >= 3, let w = Int(parts[0]), let t = Int(parts[1]) else {
                return completion(nil)
            }
            let payload = parts.dropFirst(2).joined(separator: "\u{1}")
            guard let state = parse(payload, browser: browser, window: w, tab: t) else {
                return completion(nil)
            }
            lastHit[browser] = (w, t)
            completion(state)
        }
    }

    // MARK: - Transport

    static func playPause(_ state: BrowserPlayback) {
        runOnTab(state, javascript: Self.toggleJS)
    }

    static func seek(_ state: BrowserPlayback, to seconds: TimeInterval) {
        runOnTab(state, javascript: seekJS(seconds))
    }

    private static func runOnTab(_ state: BrowserPlayback, javascript: String) {
        let script = state.browser.isSafari
            ? """
            tell application id "\(state.browser.bundleID)"
                try
                    do JavaScript "\(javascript)" in tab \(state.tab) of window \(state.window)
                end try
            end tell
            """
            : """
            tell application id "\(state.browser.bundleID)"
                try
                    execute tab \(state.tab) of window \(state.window) javascript "\(javascript)"
                end try
            end tell
            """
        PlayerBridge.runScript(script) { _ in }
    }

    // MARK: - JavaScript
    //
    // Single quotes only and no backslashes: these strings are embedded in an
    // AppleScript literal, and escaping would have to survive two layers.

    private static let readJS = """
    (function(){var e=document.querySelectorAll('video,audio');if(!e.length)return '';\
    var p=false,d=0,c=0,any=false,i,x;for(i=0;i<e.length;i++){x=e[i];\
    if(!x.paused&&!x.ended){p=true;any=true;d=x.duration||0;c=x.currentTime||0;}\
    else if(x.currentTime>0&&!any){any=true;d=x.duration||0;c=x.currentTime||0;}}\
    if(!any)return '';var s=navigator.mediaSession,m=s&&s.metadata,a='';\
    if(m&&m.artwork&&m.artwork.length)a=m.artwork[m.artwork.length-1].src;\
    var t=(m&&m.title)||document.title||'';var r=(m&&m.artist)||'';var b=(m&&m.album)||'';\
    if(!isFinite(d))d=0;\
    return [p?'playing':'paused',t,r,b,Math.round(d*1000),Math.round(c*1000),a]\
    .join(String.fromCharCode(1));})()
    """

    private static let toggleJS = """
    (function(){var e=document.querySelectorAll('video,audio'),i,x;\
    for(i=0;i<e.length;i++){x=e[i];if(!x.paused){x.pause();return 'p';}}\
    for(i=0;i<e.length;i++){x=e[i];if(x.currentTime>0){x.play();return 'r';}}\
    if(e.length){e[0].play();}return 'r';})()
    """

    private static func seekJS(_ seconds: TimeInterval) -> String {
        """
        (function(){var e=document.querySelectorAll('video,audio'),i;\
        for(i=0;i<e.length;i++){if(e[i].duration>0){e[i].currentTime=\(Int(seconds));return 's';}}\
        return '';})()
        """
    }

    // MARK: - AppleScript

    private static func singleTabScript(_ browser: BrowserApp, window: Int, tab: Int) -> String {
        let call = browser.isSafari
            ? "do JavaScript \"\(readJS)\" in tab \(tab) of window \(window)"
            : "execute tab \(tab) of window \(window) javascript \"\(readJS)\""
        return """
        tell application id "\(browser.bundleID)"
            try
                set r to \(call)
                if r is missing value then return ""
                return r as text
            on error errMsg
                return "ERR" & errMsg
            end try
        end tell
        """
    }

    private static func sweepScript(_ browser: BrowserApp) -> String {
        let call = browser.isSafari
            ? "do JavaScript \"\(readJS)\" in tb"
            : "execute tb javascript \"\(readJS)\""
        return """
        set sep to character id 1
        set fallback to ""
        set n to 0
        tell application id "\(browser.bundleID)"
            try
                repeat with wi from 1 to (count of windows)
                    repeat with ti from 1 to (count of tabs of window wi)
                        set n to n + 1
                        if n > \(tabBudget) then exit repeat
                        try
                            set tb to tab ti of window wi
                            set r to \(call)
                            if r is not missing value and (r as text) is not "" then
                                if (r as text) starts with "playing" then
                                    return (wi as text) & sep & (ti as text) & sep & (r as text)
                                else if fallback is "" then
                                    set fallback to (wi as text) & sep & (ti as text) & sep & (r as text)
                                end if
                            end if
                        end try
                    end repeat
                    if n > \(tabBudget) then exit repeat
                end repeat
            on error errMsg
                return "ERR" & errMsg
            end try
        end tell
        return fallback
        """
    }

    // MARK: - Parsing

    private static func parse(_ raw: String?, browser: BrowserApp, window: Int, tab: Int) -> BrowserPlayback? {
        guard let raw, !raw.isEmpty else { return nil }
        if raw.hasPrefix("ERR") {
            if raw.localizedCaseInsensitiveContains("javascript") {
                // Chrome and Safari both name JavaScript when the toggle is off.
                setupHint = browser.setupHint
            } else if raw.localizedCaseInsensitiveContains("authorized")
                || raw.localizedCaseInsensitiveContains("1743") {
                setupHint = "Разреши Cyclop управлять \(browser.displayName): "
                    + "Настройки → Конфиденциальность → Автоматизация"
            }
            return nil
        }
        setupHint = nil

        let parts = raw.components(separatedBy: "\u{1}")
        guard parts.count >= 6, !parts[1].isEmpty else { return nil }
        return BrowserPlayback(
            browser: browser,
            isPlaying: parts[0] == "playing",
            title: cleanTitle(parts[1], browser: browser),
            artist: parts[2],
            album: parts[3],
            duration: (Double(parts[4]) ?? 0) / 1000,
            position: (Double(parts[5]) ?? 0) / 1000,
            artworkURL: parts.count > 6 ? URL(string: parts[6]) : nil,
            window: window,
            tab: tab
        )
    }

    /// Falling back to `document.title` drags in the site name; drop it.
    private static func cleanTitle(_ title: String, browser: BrowserApp) -> String {
        var value = title
        for suffix in [" - YouTube", " — YouTube", " | Spotify", " - SoundCloud"] where value.hasSuffix(suffix) {
            value.removeLast(suffix.count)
        }
        if value.hasPrefix("("), let close = value.firstIndex(of: ")") {
            // YouTube prefixes the tab title with the unread/notification count.
            let rest = value[value.index(after: close)...].trimmingCharacters(in: .whitespaces)
            if !rest.isEmpty { value = rest }
        }
        return value
    }
}
