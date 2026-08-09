import Combine
import SwiftUI

/// First-run walkthrough.
///
/// An app whose entire interface hides in the notch has one hard problem: after
/// installing it, nothing appears to happen. No dock icon, no window, no sound —
/// it looks like a launch that failed. Everything else here can be discovered by
/// poking around; the one thing that cannot is *that the pointer has to go to the
/// notch*, and until someone does it once they have no reason to believe the app
/// is running at all.
///
/// So the middle step does not describe the gesture, it waits for it: a hint sits
/// under the notch, and the step only completes when the panel really opens.
/// Being taught by doing costs one sentence and removes the entire class of
/// "installed it, nothing happened".
struct Onboarding: View {
    /// Called when the walkthrough wants the hint under the notch shown or hidden.
    let showHint: (Bool) -> Void
    /// Called on the last step, or on skip.
    let finish: () -> Void
    /// Fires when the panel unfolds — that is what passes the gesture step.
    ///
    /// A publisher, not a flag behind a `Binding`: a plain property on a plain
    /// class invalidates nothing, so `onChange` on it never ran and the step sat
    /// on "waiting for you" with the panel wide open behind it.
    let panelOpened: AnyPublisher<Void, Never>
    /// Asked when the gesture step appears, for the case where the pointer is
    /// already there and no new opening will happen.
    let isPanelOpenNow: () -> Bool

    @State private var step = 0

    private let last = 3

    /// The gesture landed. Idempotent — the publisher can fire more than once
    /// while the step is up, and the panel opens again every time the pointer
    /// returns.
    private func passGesture() {
        guard step == 1 else { return }
        showHint(false)
        withAnimation(.easeOut(duration: 0.25)) { step = 2 }
    }

    var body: some View {
        VStack(spacing: 0) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 40)

            footer
        }
        .frame(width: 560, height: 420)
        .background(Color(nsColor: .windowBackgroundColor))
        .onChange(of: step) { _, new in
            // The hint belongs to exactly one step, and it must go away whether
            // the step was passed, skipped or navigated away from.
            showHint(new == 1)
            // Entering the step with the panel already unfolded: nothing further
            // will open, so the step is passed on arrival.
            if new == 1, isPanelOpenNow() { passGesture() }
        }
        .onReceive(panelOpened) { _ in passGesture() }
        .onDisappear { showHint(false) }
    }

    // MARK: - Steps

    @ViewBuilder
    private var content: some View {
        switch step {
        case 0: welcome
        case 1: gesture
        case 2: tabs
        default: menuBar
        }
    }

    private var welcome: some View {
        VStack(spacing: 18) {
            MarkGlyph()
                .frame(width: 108, height: 88)
            Text(localized("CAVO Notch"))
                .font(.system(size: 26, weight: .semibold))
            Text(localized("The notch is now a panel. A player, a shelf for files, the clipboard, your meetings, a translator, notes and a timer — all in the space above your screen that was doing nothing."))
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var gesture: some View {
        VStack(spacing: 18) {
            // Points the same way the person has to move: up, off the top of the
            // window, towards the thing being described.
            Image(systemName: "arrow.up")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Color.accentColor)
                .symbolEffect(.pulse)
            Text(localized("Move the pointer to the notch"))
                .font(.system(size: 22, weight: .semibold))
                .multilineTextAlignment(.center)
            Text(localized("Up to the top of the screen, in the middle. The panel unfolds by itself and folds back when the pointer leaves. Nothing to click."))
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text(localized("Waiting for you…"))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.tertiary)
                .padding(.top, 4)
        }
    }

    private var tabs: some View {
        VStack(spacing: 14) {
            Text(localized("Eight tabs on two rails"))
                .font(.system(size: 22, weight: .semibold))
            Text(localized("Hover an icon to switch. A pointer passing through switches nothing — it has to come to rest."))
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            // Two columns, laid out like the rails themselves.
            HStack(alignment: .top, spacing: 26) {
                tabList([
                    ("music.note", localized("Music")),
                    ("tray.full.fill", localized("Shelf")),
                    ("list.clipboard.fill", localized("Clipboard")),
                    ("pin.fill", localized("Snippets")),
                ])
                tabList([
                    ("calendar", localized("Calendar")),
                    ("translate", localized("Translate")),
                    ("note.text", localized("Notes")),
                    ("timer", localized("Timer")),
                ])
            }
            .padding(.top, 6)
        }
    }

    private func tabList(_ items: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            ForEach(items, id: \.1) { item in
                HStack(spacing: 9) {
                    Image(systemName: item.0)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 18)
                    Text(item.1)
                        .font(.system(size: 12.5))
                }
            }
        }
    }

    private var menuBar: some View {
        VStack(spacing: 18) {
            Image(systemName: "menubar.arrow.up.rectangle")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(Color.accentColor)
            Text(localized("Everything else is in the menu bar"))
                .font(.system(size: 22, weight: .semibold))
                .multilineTextAlignment(.center)
            Text(localized("The icon by the clock opens the panel, hides the contents of any tab for screen sharing, switches launch at login, and shows this walkthrough again."))
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text(localized("One permission, and only on a button: the Calendar tab asks, nothing else does."))
                .font(.system(size: 11.5))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 12) {
            // Dots rather than "2 of 4": four steps is short enough to see.
            HStack(spacing: 6) {
                ForEach(0...last, id: \.self) { i in
                    Circle()
                        .fill(i == step ? Color.accentColor : Color.secondary.opacity(0.28))
                        .frame(width: 6, height: 6)
                }
            }

            Spacer()

            if step < last {
                Button(localized("Skip")) { finish() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }

            // The gesture step has no Next: the way past it is doing it. Leaving a
            // button there would let someone skip the one thing they must learn
            // and then wonder why the app appears to do nothing.
            if step != 1 {
                Button(step == last ? localized("Done") : localized("Next")) {
                    if step == last {
                        finish()
                    } else {
                        withAnimation(.easeOut(duration: 0.2)) { step += 1 }
                    }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
        .background(.quaternary.opacity(0.35))
    }
}

/// The product mark, drawn from the same geometry as the app icon: a panel
/// hanging out of the top edge of a display.
struct MarkGlyph: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let barH = h * 0.17
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: w * 0.14, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color(red: 0.039, green: 0.400, blue: 1.0),
                                     Color(red: 0.043, green: 0.251, blue: 0.651)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .overlay(alignment: .top) {
                        Rectangle()
                            .fill(Color(red: 0.024, green: 0.055, blue: 0.133))
                            .frame(height: barH)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: w * 0.14, style: .continuous))

                NotchShape(topRadius: w * 0.10, bottomRadius: w * 0.13)
                    .fill(.white)
                    .frame(width: w * 0.72, height: h * 0.62)
                    .offset(y: barH * 0.45)
            }
        }
    }
}
