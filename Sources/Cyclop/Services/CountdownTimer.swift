import AppKit

/// A countdown with a pomodoro cycle on top of it.
///
/// Announces itself three ways, because a timer that goes off unnoticed has done
/// nothing: a chime, the remaining time beside the menu bar icon, and a system
/// notification booked at the due date (`TimerNotifier`). The notch itself stays
/// black while the panel is collapsed, which is why the menu bar carries the
/// running number — and why the banner matters at all, since neither the chime
/// nor the menu bar reaches someone in full screen on another display.
@MainActor
final class CountdownTimer: ObservableObject {
    /// What the current run is for. A plain countdown is `.single`; the pomodoro
    /// preset runs `.work` and then hands over to `.rest` by itself, which is
    /// the whole difference between the two.
    enum Phase: String {
        case single, work, rest

        var title: String {
            switch self {
            case .single: return localized("Timer")
            case .work: return localized("Focus")
            case .rest: return localized("Break")
            }
        }
    }

    /// Minutes offered as one press. Five is the "put the kettle on" case, ten
    /// the "answer this before it rots" one, twenty-five the pomodoro, and
    /// forty-five is a lecture, a wash cycle or a parking meter.
    static let presets = [5, 10, 25, 45]
    static let pomodoroWork = 25
    static let pomodoroRest = 5

    /// When the current run is due, or nil when nothing is running. This is the
    /// state — `remaining` below is derived from it once a second, rather than
    /// decremented, so a tick that arrives late or not at all cannot make the
    /// countdown drift away from the wall clock.
    @Published private(set) var endDate: Date?
    /// Whole seconds left, which is what both the pane and the menu bar show.
    @Published private(set) var remaining: TimeInterval = 0
    @Published private(set) var phase: Phase = .single
    /// Set when a run reaches zero and cleared by the next start or by
    /// `acknowledge()`. The pane paints itself with it, so a timer that ended
    /// while nobody was looking still says so when the panel is next opened.
    @Published private(set) var isFinished = false

    /// Total length of the current run, for the ring. Kept apart from the dates
    /// because pausing rewrites `endDate` and `+1 min` extends it: computing the
    /// span from those would make the ring jump.
    private(set) var total: TimeInterval = 0
    /// Seconds left at the moment of pausing. Non-nil *is* the paused state.
    @Published private(set) var pausedRemaining: TimeInterval?

    var isRunning: Bool { endDate != nil && pausedRemaining == nil }
    var isPaused: Bool { pausedRemaining != nil }
    var isIdle: Bool { endDate == nil && pausedRemaining == nil }

    /// Fraction elapsed, 0…1. The ring reads this.
    var progress: Double {
        guard total > 0 else { return 0 }
        return min(1, max(0, 1 - remaining / total))
    }

    /// Compact form for the menu bar: 24:59, or 1:04:00 once an hour is on the
    /// clock. Minutes are padded and hours are not, the way every clock does it.
    var clock: String {
        let seconds = Int(remaining.rounded(.up))
        let (h, m, s) = (seconds / 3600, (seconds % 3600) / 60, seconds % 60)
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%d:%02d", m, s)
    }

    /// Ticks only while a run is live, and is torn down the moment one ends: a
    /// repeating timer left behind is exactly the kind of idle work this app is
    /// built not to do.
    private var ticker: Timer?
    /// Fires once, exactly at `endDate`.
    ///
    /// The ticker above is for the digits and is deliberately lazy — half a
    /// second apart with tolerance on top, so the system can coalesce it with
    /// whatever else it is waking for. That is fine for a number on screen and
    /// not fine for the alarm: noticing the end on the next display tick rings
    /// it up to 0.7 s late, which measured at 6.3 s on a run due at 5.6 s. A
    /// countdown may render lazily; it may not go off late.
    private var deadline: Timer?
    private var sound: NSSound?

    private static let endKey = "timer.endDate"
    private static let phaseKey = "timer.phase"
    private static let totalKey = "timer.total"

    // MARK: - Lifecycle

    /// Picks a run back up after a relaunch.
    ///
    /// A run whose end has already passed is dropped in silence rather than
    /// announced: the alarm for it was due while the app was not running, and
    /// ringing it now — possibly hours late, possibly at login — would be
    /// telling the truth at the least useful moment.
    func restore() {
        let defaults = UserDefaults.standard
        guard let end = defaults.object(forKey: Self.endKey) as? Date else { return }
        guard end > Date() else {
            clearPersisted()
            return
        }
        phase = Phase(rawValue: defaults.string(forKey: Self.phaseKey) ?? "") ?? .single
        total = defaults.double(forKey: Self.totalKey)
        endDate = end
        tick()
        startTicking()
        scheduleNotification()
    }

    /// Stops the ticking and leaves the due date on disk.
    ///
    /// What quitting does. Not `stop()`: that is the user cancelling a timer,
    /// and forgetting a run because the app was restarted is not the same as
    /// being told to forget it.
    func suspend() {
        stopTicking()
        stopSound()
        // The banner is left booked on purpose: the due date survives a quit, so
        // the notification should ring even with the app not running.
    }

    func stop() {
        endDate = nil
        pausedRemaining = nil
        remaining = 0
        total = 0
        phase = .single
        isFinished = false
        stopTicking()
        stopSound()
        clearPersisted()
        TimerNotifier.cancel()
        TimerNotifier.clearDelivered()
    }

    // MARK: - Starting

    func start(minutes: Int) {
        start(seconds: TimeInterval(minutes) * 60, phase: .single)
    }

    /// 25 minutes of work which then hands over to 5 of rest on its own.
    func startPomodoro() {
        start(seconds: TimeInterval(Self.pomodoroWork) * 60, phase: .work)
    }

    private func start(seconds: TimeInterval, phase: Phase) {
        stopSound()
        isFinished = false
        pausedRemaining = nil
        self.phase = phase
        total = seconds
        endDate = Date().addingTimeInterval(seconds)
        tick()
        startTicking()
        persist()
        // Asked here rather than at launch: the first press on a preset is the
        // moment the question makes sense.
        TimerNotifier.requestIfNeeded()
        TimerNotifier.clearDelivered()
        scheduleNotification()
    }

    /// Books the banner for the current deadline, naming the phase so a pomodoro
    /// handover says which half just ended.
    private func scheduleNotification() {
        guard let endDate else { return }
        let title: String
        let body: String
        switch phase {
        case .work:
            title = localized("Focus done")
            body = localized("Break for %d min", Self.pomodoroRest)
        case .rest:
            title = localized("Break over")
            body = localized("Back to it")
        case .single:
            title = localized("Timer")
            body = localized("Time is up")
        }
        TimerNotifier.schedule(at: endDate, title: title, body: body)
    }

    // MARK: - While running

    func pause() {
        guard let endDate, pausedRemaining == nil else { return }
        pausedRemaining = max(0, endDate.timeIntervalSinceNow)
        remaining = pausedRemaining ?? 0
        stopTicking()
        TimerNotifier.cancel()
        // The stored end date is now meaningless — a paused run has no due time.
        // Left in place, a relaunch would resume a countdown that was on hold.
        clearPersisted()
    }

    func resume() {
        guard let left = pausedRemaining else { return }
        pausedRemaining = nil
        endDate = Date().addingTimeInterval(left)
        tick()
        startTicking()
        persist()
        scheduleNotification()
    }

    /// One more minute, on the run in progress. Extends the total as well, so
    /// the ring stays honest instead of snapping backwards.
    func extend(minutes: Int = 1) {
        let seconds = TimeInterval(minutes) * 60
        total += seconds
        if let left = pausedRemaining {
            pausedRemaining = left + seconds
            remaining = left + seconds
            return
        }
        guard let endDate else { return }
        self.endDate = endDate.addingTimeInterval(seconds)
        // The due moment moved, so the exact one-shot aimed at the old one is
        // now wrong — without this, +1 min still rang at the original time. The
        // booked banner is wrong for the same reason and is re-booked below.
        scheduleDeadline()
        tick()
        persist()
        scheduleNotification()
    }

    /// Silences the alarm and clears the finished state without starting
    /// anything. The pane's way out of "done" that is not another timer.
    func acknowledge() {
        isFinished = false
        stopSound()
        TimerNotifier.clearDelivered()
    }

    // MARK: - Ticking

    private func startTicking() {
        stopTicking()
        // Tolerance lets the system coalesce this with whatever else it is
        // waking for. A second-hand countdown does not need to be woken exactly.
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        timer.tolerance = 0.2
        // `.common` so the countdown keeps running while a menu is open or the
        // panel is being dragged — a run loop in a tracking mode ignores the
        // default one, and a timer that stalls whenever the menu bar item is
        // held open is a timer nobody can trust.
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
        scheduleDeadline()
    }

    /// Arms the exact one-shot for the current `endDate`. Re-armed by anything
    /// that moves that date, which is why it lives beside the ticker rather than
    /// inside `start`.
    private func scheduleDeadline() {
        deadline?.invalidate()
        guard let endDate else { return }
        let timer = Timer(fire: endDate, interval: 0, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        // No tolerance: this is the one wake-up in the app that has a right
        // moment rather than a rough one.
        timer.tolerance = 0
        RunLoop.main.add(timer, forMode: .common)
        deadline = timer
    }

    private func stopTicking() {
        ticker?.invalidate()
        ticker = nil
        deadline?.invalidate()
        deadline = nil
    }

    private func tick() {
        guard let endDate else { return }
        let left = endDate.timeIntervalSinceNow
        guard left > 0 else {
            finish()
            return
        }
        remaining = left
    }

    private func finish() {
        let ended = phase
        endDate = nil
        remaining = 0
        stopTicking()
        clearPersisted()

        // Work hands over to rest by itself; rest and a plain countdown stop and
        // say so. Chaining another work phase after the break is deliberately
        // not automatic — a cycle that restarts itself is one nobody ever
        // decided to continue.
        if ended == .work {
            // Rest is armed *before* the chime, not after: `start` silences
            // whatever is playing — which is right when a person starts a new
            // timer over a ringing one, and wrong here, where it cut off the
            // very sound announcing the handover a millisecond after it began.
            start(seconds: TimeInterval(Self.pomodoroRest) * 60, phase: .rest)
            play()
            return
        }
        isFinished = true
        play()
    }

    // MARK: - Alarm

    /// A system sound, played once. Named rather than bundled: the app ships
    /// 2 MB and one of the reasons is that it carries no assets it can borrow.
    private func play() {
        stopSound()
        guard let sound = NSSound(named: "Glass") else { return }
        self.sound = sound
        sound.play()
    }

    private func stopSound() {
        sound?.stop()
        sound = nil
    }

    // MARK: - Persistence

    private func persist() {
        let defaults = UserDefaults.standard
        defaults.set(endDate, forKey: Self.endKey)
        defaults.set(phase.rawValue, forKey: Self.phaseKey)
        defaults.set(total, forKey: Self.totalKey)
    }

    private func clearPersisted() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: Self.endKey)
        defaults.removeObject(forKey: Self.phaseKey)
        defaults.removeObject(forKey: Self.totalKey)
    }
}
