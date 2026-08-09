import AppKit
import UserNotifications

/// System notification when a countdown ends.
///
/// The sound alone is enough while you are at the machine with the volume up. It
/// is not enough on a second display in full screen, in a meeting with the Mac
/// muted, or when the panel has not been opened in an hour — which is exactly
/// when a timer matters. So this is the one place the app does ask for a second
/// permission, and it asks the first time a timer is actually started rather
/// than at launch: a prompt on first run explains nothing.
///
/// Scheduled ahead at the due date rather than posted at the moment of ringing,
/// so it fires on time even if the app is busy, and cancelled by anything that
/// moves or removes the deadline.
@MainActor
enum TimerNotifier {
    /// Off switch, for the days when the banners are the annoying part.
    static let enabledKey = "timerNotifications"

    static var isEnabled: Bool {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: enabledKey) != nil else { return true }
        return defaults.bool(forKey: enabledKey)
    }

    /// One identifier, reused: there is only ever one countdown, so scheduling a
    /// new one must replace the old rather than queue behind it.
    private static let requestID = "cyclop.timer.end"

    /// True once the system has been asked, so a run of five pomodoros does not
    /// ask five times. The answer itself lives with the system, not here.
    private static var didRequest = false

    private static var center: UNUserNotificationCenter? {
        // An app running straight from SwiftPM has no bundle identifier, and
        // `current()` traps rather than returning nil in that case. The built
        // .app always has one; this keeps `swift run` from dying on launch.
        guard Bundle.main.bundleIdentifier != nil else { return nil }
        return UNUserNotificationCenter.current()
    }

    static func requestIfNeeded() {
        guard isEnabled, !didRequest, let center else { return }
        didRequest = true
        center.requestAuthorization(options: [.alert, .sound]) { _, error in
            if let error {
                NSLog("Cyclop: notification permission failed: \(error.localizedDescription)")
            }
        }
    }

    /// Books the banner for `date`. Silent — the app plays its own chime, and two
    /// sounds a millisecond apart read as a glitch rather than as an alarm.
    static func schedule(at date: Date, title: String, body: String) {
        guard isEnabled, let center else { return }
        let interval = date.timeIntervalSinceNow
        // A trigger in the past is rejected by the system with an error; there is
        // nothing to book for a deadline that has already passed.
        guard interval > 0.5 else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body

        let request = UNNotificationRequest(
            identifier: requestID,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        )
        center.add(request) { error in
            if let error {
                NSLog("Cyclop: could not schedule notification: \(error.localizedDescription)")
            }
        }
    }

    /// Drops the pending banner. Called by everything that ends or moves a run —
    /// a stopped timer that still announces itself later is worse than one that
    /// never announced itself at all.
    static func cancel() {
        center?.removePendingNotificationRequests(withIdentifiers: [requestID])
    }

    /// Clears a banner already sitting in Notification Centre, so acknowledging
    /// the timer in the panel also clears it from the corner of the screen.
    static func clearDelivered() {
        center?.removeDeliveredNotifications(withIdentifiers: [requestID])
    }
}
