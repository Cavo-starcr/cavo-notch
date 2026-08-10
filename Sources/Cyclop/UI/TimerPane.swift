import SwiftUI

/// The countdown: a ring with the time inside it, and the presets beside it.
///
/// Two columns rather than a stack, because the panel is 620 wide and 208 tall —
/// wide and shallow. A ring big enough to read from across the desk plus four
/// buttons under it would not fit vertically; side by side, both are comfortable.
struct TimerPane: View {
    @ObservedObject var timer: CountdownTimer

    var body: some View {
        HStack(spacing: 22) {
            dial
            controls
        }
        .padding(.top, 2)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(Theme.contentAnimation, value: timer.isIdle)
        .animation(Theme.contentAnimation, value: timer.isFinished)
    }

    // MARK: - Dial

    private var dial: some View {
        ZStack {
            Circle()
                .stroke(Theme.surface, lineWidth: 6)

            Circle()
                .trim(from: 0, to: timer.isIdle ? 0 : timer.progress)
                // A gradient along the sweep, dim at the tail and full at the
                // head: the ring reads as travelling, not merely filling.
                .stroke(
                    AngularGradient(
                        colors: [ringColor.opacity(0.35), ringColor],
                        center: .center,
                        startAngle: .degrees(0),
                        endAngle: .degrees(360 * max(timer.progress, 0.001))
                    ),
                    style: StrokeStyle(lineWidth: 6, lineCap: .round)
                )
                // Glow is a flourish, so it obeys the motion level: maximum gets
                // the halo, calm gets a clean line.
                .shadow(
                    color: Appearance.shared.effectiveMotion == .max && timer.isRunning
                        ? ringColor.opacity(0.55) : .clear,
                    radius: 7
                )
                // Twelve o'clock, clockwise: a ring that starts at three and has
                // to be read anti-clockwise is a puzzle, not a clock.
                .rotationEffect(.degrees(-90))
                // Only the second-by-second creep is animated. A start, a stop
                // or a fresh preset resets the trim to a distant value, and
                // animating that sweeps the ring the long way round.
                .animation(.linear(duration: 0.5), value: timer.progress)

            VStack(spacing: 2) {
                Text(timer.isIdle ? "0:00" : timer.clock)
                    .font(.system(size: 30, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white)
                    // Digits are replaced in place; without this the whole line
                    // is rebuilt every second and the width twitches.
                    .contentTransition(.numericText(countsDown: true))
                Text(label)
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(labelColor)
                    .textCase(.uppercase)
            }
        }
        .frame(width: 124, height: 124)
    }

    /// The one place the three states are told apart by colour: rest is green
    /// because it is permission to stop, a finished timer is amber because it
    /// wants an answer, and everything else is plain white.
    private var ringColor: Color {
        if timer.isFinished { return Color(red: 1, green: 0.72, blue: 0.28) }
        if timer.phase == .rest { return Color(red: 0.42, green: 0.85, blue: 0.55) }
        // The running ring carries the accent: it is the one live element on the
        // tab, and the accent exists to mark exactly that kind of thing.
        return timer.isPaused ? Theme.secondary : Theme.tint
    }

    private var label: String {
        if timer.isFinished { return localized("Done") }
        if timer.isPaused { return localized("Paused") }
        if timer.isIdle { return localized("Ready") }
        return timer.phase.title
    }

    private var labelColor: Color {
        timer.isFinished || timer.phase == .rest ? ringColor.opacity(0.9) : Theme.tertiary
    }

    // MARK: - Controls

    private var controls: some View {
        VStack(alignment: .leading, spacing: 10) {
            presets
            Divider().overlay(Theme.hairline)
            transport
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var presets: some View {
        HStack(spacing: 6) {
            ForEach(CountdownTimer.presets, id: \.self) { minutes in
                Button {
                    timer.start(minutes: minutes)
                } label: {
                    Text(localized("%d min", minutes))
                        .font(.system(size: 11, weight: .medium))
                        .frame(minWidth: 52)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Theme.surface)
                        )
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            }

            Button {
                timer.startPomodoro()
            } label: {
                // The one preset that is a cycle rather than a length, so it is
                // named instead of numbered.
                HStack(spacing: 4) {
                    Image(systemName: "timer")
                    Text(localized("Pomodoro"))
                }
                .font(.system(size: 11, weight: .medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(timer.phase == .work || timer.phase == .rest ? Theme.surfaceHover : Theme.surface)
                )
                .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var transport: some View {
        if timer.isFinished {
            // Nothing to pause and nothing to stop: the only thing left to do
            // with a finished timer is put it away, so that is the only button.
            HStack(spacing: 8) {
                action(localized("Dismiss"), symbol: "checkmark") { timer.acknowledge() }
                Text(localized("Time is up"))
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.secondary)
            }
        } else if timer.isIdle {
            Text(localized("Pick a length, or start a pomodoro"))
                .font(.system(size: 10))
                .foregroundStyle(Theme.tertiary)
        } else {
            HStack(spacing: 8) {
                if timer.isPaused {
                    action(localized("Resume"), symbol: "play.fill") { timer.resume() }
                } else {
                    action(localized("Pause"), symbol: "pause.fill") { timer.pause() }
                }
                action(localized("+1 min"), symbol: "plus") { timer.extend() }
                action(localized("Stop"), symbol: "stop.fill") { timer.stop() }
            }
        }
    }

    private func action(_ title: String, symbol: String, run: @escaping () -> Void) -> some View {
        Button(action: run) {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 9, weight: .bold))
                Text(title)
                    .font(.system(size: 11, weight: .medium))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Theme.surface)
            )
            .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
    }
}

/// The countdown in the panel header, watching the store directly.
///
/// The view model forwards store changes only while the panel is open, which is
/// exactly right for everything else and wrong here: this ticks every second
/// and is the one number in the header that must not be a second stale.
struct TimerCounter: View {
    @ObservedObject var timer: CountdownTimer

    var body: some View {
        if timer.isFinished {
            Text(localized("Done"))
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color(red: 1, green: 0.72, blue: 0.28))
        } else if !timer.isIdle {
            Text(timer.clock)
                .font(.system(size: 10, weight: .medium).monospacedDigit())
                .foregroundStyle(timer.isPaused ? Theme.tertiary : Color.white.opacity(0.8))
        }
    }
}
