import AppKit
import EventKit

/// Today's meetings, and the link that joins the next one.
///
/// Access is requested only when the user first opens the calendar tab: it is
/// the one permission Cyclop needs at all, and nobody should be asked for it
/// just because the app launched.
@MainActor
final class CalendarStore: ObservableObject {
    enum Access {
        case notRequested
        case granted
        case denied
    }

    struct Meeting: Identifiable {
        let id: String
        let title: String
        let start: Date
        let end: Date
        let calendarColor: NSColor
        let link: URL?
        let provider: String?

        var isRunning: Bool {
            let now = Date()
            return start <= now && now < end
        }

        func overlaps(_ other: Meeting) -> Bool {
            start < other.end && end > other.start
        }
    }

    @Published private(set) var access: Access = .notRequested
    @Published private(set) var meetings: [Meeting] = []
    /// Recomputed on a timer so the countdown in the header stays honest.
    @Published private(set) var now = Date()

    private let store = EKEventStore()
    private var timer: Timer?
    private var observer: Any?
    /// Whether the panel is open. The half-minute tick serves eyes only — it
    /// keeps the countdown honest and drops meetings as they end — so it runs
    /// exactly while there are eyes.
    private var isActive = false
    /// A day-long horizon leaves the tab empty every evening, which is exactly
    /// when one wonders what tomorrow looks like. A week is still glanceable
    /// because only the next meeting gets the large treatment.
    private let horizon: TimeInterval = 7 * 24 * 3600

    var next: Meeting? {
        meetings.first { $0.end > Date() }
    }

    var upcoming: [Meeting] {
        guard let next else { return [] }
        return meetings.filter { $0.id != next.id && $0.end > Date() }
    }

    // MARK: - Lifecycle

    func start() {
        access = Self.currentAccess()
        guard access == .granted else { return }
        observe()
        reload()
    }

    func stop() {
        stopTimer()
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
    }

    /// Panel opened or closed. Opening refreshes at once — the countdown must
    /// be right on the first frame, not thirty seconds in — and starts the
    /// tick; closing stops it. Meetings still change while the panel is
    /// closed, but `EKEventStoreChanged` covers that without a clock.
    func setActive(_ active: Bool) {
        isActive = active
        guard active else { return stopTimer() }
        guard access == .granted else { return }
        tick()
        startTimer()
    }

    /// Called when the calendar tab is shown. Never prompts — it only notices
    /// that access was granted elsewhere, or since last launch.
    func refreshAccess() {
        access = Self.currentAccess()
        guard access == .granted else { return }
        observe()
        reload()
        if isActive { startTimer() }
    }

    /// Prompts. Only ever called from the button the user presses.
    func requestAccess() {
        guard Self.currentAccess() == .notRequested else {
            refreshAccess()
            return
        }
        store.requestFullAccessToEvents { [weak self] granted, _ in
            Task { @MainActor in
                guard let self else { return }
                self.access = granted ? .granted : .denied
                guard granted else { return }
                self.observe()
                self.reload()
                if self.isActive { self.startTimer() }
            }
        }
    }

    private static func currentAccess() -> Access {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: return .granted
        case .notDetermined: return .notRequested
        default: return .denied
        }
    }

    /// Calendars unchecked in Calendar.app's sidebar. EventKit has no public
    /// notion of this at all — "shown or not" is Calendar.app's own UI state,
    /// not calendar data, so it lives in Calendar.app's preferences instead.
    /// The identifiers there are the same ones EventKit hands out: Calendar.app
    /// and EventKit both read the same underlying calendar store.
    private static func hiddenCalendarIdentifiers() -> Set<String> {
        let stored = CFPreferencesCopyAppValue(
            "DisabledCalendars" as CFString, "com.apple.iCal" as CFString
        )
        // No key at all is the ordinary case — it means nothing is hidden.
        guard let stored else { return [] }

        // A key that is present but no longer shaped the way we read it is the
        // case worth saying out loud. This is Calendar.app's own storage, not an
        // API with a contract: the day it is restructured, this function starts
        // returning an empty set, which is indistinguishable from "nothing is
        // hidden" and quietly puts the hidden calendars back on screen. Nobody
        // files that as a bug — they just see meetings that are not theirs.
        guard let disabled = stored as? [String: [String]] else {
            NSLog("Cyclop: com.apple.iCal DisabledCalendars is no longer [String: [String]] — hidden calendars will be shown again")
            return []
        }
        return Set(disabled.values.flatMap { $0 })
    }

    private func observe() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: store, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload() }
        }
    }

    private func startTimer() {
        guard timer == nil else { return }
        // Half a minute is enough for a countdown shown in whole minutes, and
        // the generous tolerance lets the system fold the wake-up into others.
        let timer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer.tolerance = 5
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        now = Date()
        // Drop finished meetings without a full refetch.
        if meetings.contains(where: { $0.end <= now }) {
            meetings.removeAll { $0.end <= now }
        }
    }

    // MARK: - Which calendars count
    //
    // A Mac with a work Google account and a personal iCloud one has both in
    // EventKit — Google calendars arrive through Internet Accounts and need no
    // API, no OAuth and no network of our own. That is the whole "Google or
    // Apple calendar" question answered by the system; what was missing is the
    // choice of *which* of them belong in a panel you glance at all day, since
    // "the next meeting" from the wrong account is worse than no meeting at all.

    /// Calendars the user has switched off here, by identifier.
    ///
    /// Exclusions rather than inclusions on purpose: a calendar added later —
    /// a new project, a shared team one — then shows up by itself instead of
    /// silently missing from the panel until someone notices.
    private static let excludedKey = "calendar.excluded"

    private(set) var excluded: Set<String> = {
        Set(UserDefaults.standard.stringArray(forKey: CalendarStore.excludedKey) ?? [])
    }()

    /// One account's calendars, for the picker.
    struct Group: Identifiable {
        let id: String
        /// "iCloud", "Google", "Local" — whatever the account calls itself.
        let account: String
        let calendars: [Entry]
    }

    struct Entry: Identifiable {
        let id: String
        let title: String
        let color: NSColor
        let on: Bool
    }

    /// Everything EventKit offers, grouped by account, minus what Calendar.app
    /// itself hides — a calendar unticked over there is not a choice to re-offer.
    func groups() -> [Group] {
        guard access == .granted else { return [] }
        let hidden = Self.hiddenCalendarIdentifiers()
        let visible = store.calendars(for: .event).filter { !hidden.contains($0.calendarIdentifier) }
        let bySource = Dictionary(grouping: visible) { $0.source.title }
        return bySource.keys.sorted().map { title in
            Group(
                id: title,
                account: title,
                calendars: (bySource[title] ?? [])
                    .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
                    .map {
                        Entry(
                            id: $0.calendarIdentifier,
                            title: $0.title,
                            color: $0.color ?? .systemBlue,
                            on: !excluded.contains($0.calendarIdentifier)
                        )
                    }
            )
        }
    }

    private func activeCalendars() -> [EKCalendar] {
        let hidden = Self.hiddenCalendarIdentifiers()
        return store.calendars(for: .event).filter {
            !hidden.contains($0.calendarIdentifier) && !excluded.contains($0.calendarIdentifier)
        }
    }

    /// Flips one calendar and refetches. Refusing to switch off the last one:
    /// an empty calendar tab looks broken rather than filtered, and the way to
    /// have no meetings on screen is to not open the tab.
    func toggle(_ id: String) {
        var next = excluded
        if next.contains(id) {
            next.remove(id)
        } else {
            let total = groups().reduce(0) { $0 + $1.calendars.count }
            guard next.count + 1 < total else { return }
            next.insert(id)
        }
        excluded = next
        UserDefaults.standard.set(Array(next), forKey: Self.excludedKey)
        objectWillChange.send()
        reload()
    }

    /// True when something is filtered out — the tab shows it, so a short list
    /// is never mistaken for an empty week.
    var isFiltered: Bool { !excluded.isEmpty }

    // MARK: - Loading

    func reload() {
        guard access == .granted else { return }
        let calendars = activeCalendars()
        let start = Date()
        let predicate = store.predicateForEvents(
            withStart: start,
            end: start.addingTimeInterval(horizon),
            calendars: calendars
        )
        meetings = store.events(matching: predicate)
            .filter { !$0.isAllDay && $0.status != .canceled }
            .sorted { $0.startDate < $1.startDate }
            .map { event in
                let link = MeetingLink.find(in: event)
                return Meeting(
                    id: event.eventIdentifier ?? "\(event.startDate.timeIntervalSince1970)-\(event.title ?? "")",
                    title: event.title ?? localized("Untitled"),
                    start: event.startDate,
                    end: event.endDate,
                    calendarColor: event.calendar.color ?? .systemBlue,
                    link: link,
                    provider: link.flatMap(MeetingLink.provider)
                )
            }
        now = Date()
    }

    func join(_ meeting: Meeting) {
        // Checked a second time, at the point of opening. The link comes out
        // of an event, and an event can be sent by anyone: a calendar
        // invitation needs no acquaintance, only an address.
        guard let link = meeting.link, MeetingLink.isJoinable(link) else { return }
        NSWorkspace.shared.open(link)
    }

    func openCalendarApp() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Calendar.app"))
    }
}

/// Finds the video call in an event. Providers put the link wherever they like:
/// Google Meet in the notes, Zoom often in the location, Teams in both.
///
/// Only links to the known hosts are ever returned, and only over https. An
/// event is not the user's own text: anyone who knows the address can put one
/// in the calendar, and whatever it carries would otherwise arrive as a button
/// that says "Join" and opens it. A meeting with an unrecognised link keeps its
/// row and loses the button — the link is still in the event, one click away in
/// Calendar, where it looks like what it is.
enum MeetingLink {
    private static let hosts = [
        "meet.google.com": "Google Meet",
        "zoom.us": "Zoom",
        "teams.microsoft.com": "Teams",
        "teams.live.com": "Teams",
        "webex.com": "Webex",
        "whereby.com": "Whereby",
        "meet.jit.si": "Jitsi",
        "discord.gg": "Discord",
        "telemost.yandex.ru": "Телемост",
    ]

    private static let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)

    static func find(in event: EKEvent) -> URL? {
        let haystacks = [event.location, event.notes, event.url?.absoluteString].compactMap { $0 }
        for text in haystacks {
            if let url = firstKnownLink(in: text) { return url }
        }
        return nil
    }

    /// Everything the join button is allowed to open.
    static func isJoinable(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https" && provider(for: url) != nil
    }

    private static func firstKnownLink(in text: String) -> URL? {
        guard let detector else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        for match in detector.matches(in: text, range: range) {
            guard let url = match.url,
                  url.scheme?.lowercased() == "https",
                  let host = url.host?.lowercased() else { continue }
            if hosts.keys.contains(where: { host == $0 || host.hasSuffix(".\($0)") }) { return url }
        }
        return nil
    }

    static func provider(for url: URL) -> String? {
        guard let host = url.host?.lowercased() else { return nil }
        return hosts.first { host == $0.key || host.hasSuffix(".\($0.key)") }?.value
    }
}
