import SwiftUI

/// The appearance settings: choices on the left, a live panel on the right.
///
/// Design settings without a preview are a guessing game played through a menu,
/// so the preview is not a picture — it is the same `NotchShape`, the same
/// `PanelBorder` and the same springs the real panel uses, driven by the same
/// `Appearance` object. What you see here is what the notch does, by
/// construction rather than by discipline.
struct AppearancePane: View {
    @ObservedObject var appearance: Appearance
    @ObservedObject private var weather = WeatherService.shared

    /// Drives the preview's unfold. Re-toggled to replay.
    @State private var previewOpen = true
    /// The city as typed, before the geocoder has had its say.
    @State private var cityDraft = WeatherService.shared.placeName

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            controls
                .frame(width: 300)
                .padding(20)

            Divider()

            preview
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 660, height: 440)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Controls

    private var controls: some View {
        VStack(alignment: .leading, spacing: 18) {
            section(localized("Border")) {
                HStack(spacing: 8) {
                    ForEach(Appearance.Border.allCases) { border in
                        borderSwatch(border)
                    }
                }
            }

            section(localized("Accent")) {
                HStack(spacing: 8) {
                    ForEach(Appearance.Accent.allCases) { accent in
                        accentSwatch(accent)
                    }
                }
            }

            section(localized("Motion")) {
                Picker("", selection: $appearance.motion) {
                    ForEach(Appearance.Motion.allCases) { motion in
                        Text(motion.title).tag(motion)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                // A motion choice is heard, not read: replay the unfold with the
                // newly chosen spring the moment it changes.
                .onChange(of: appearance.motion) { _, _ in replay() }
            }

            section(localized("Material")) {
                Picker("", selection: $appearance.material) {
                    ForEach(Appearance.Material.allCases) { material in
                        Text(material.title).tag(material)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            Divider()

            Toggle(isOn: $weather.enabled) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(localized("Weather in the notch"))
                        .font(.system(size: 12.5))
                    Text(localized("Temperature on the wings when nothing is playing. Checks Open-Meteo every 20 minutes — the app's only network call."))
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .toggleStyle(.switch)
            .controlSize(.small)

            if weather.enabled {
                HStack(spacing: 6) {
                    TextField(localized("City"), text: $cityDraft)
                        .textFieldStyle(.roundedBorder)
                        .controlSize(.small)
                        .onSubmit { Task { await weather.setCity(cityDraft) } }
                    weatherStatus
                }
                .padding(.leading, 2)
            }

            Toggle(isOn: $appearance.liveMusic) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(localized("Music in the closed notch"))
                        .font(.system(size: 12.5))
                    // The cost is stated where the switch is, not in a FAQ: this
                    // is the one option that trades battery for looks.
                    Text(localized("Artwork and a level meter while something plays. Draws continuously, so it costs a little CPU."))
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .toggleStyle(.switch)
            .controlSize(.small)

            Spacer(minLength: 0)
        }
    }

    /// One glance answers "did it take": the resolved place proves the typo
    /// went through, the warning says why the wing is empty.
    @ViewBuilder
    private var weatherStatus: some View {
        switch weather.status {
        case .looking:
            ProgressView().controlSize(.small).scaleEffect(0.6)
        case .cityNotFound:
            Text(localized("City not found"))
                .font(.system(size: 10))
                .foregroundStyle(.orange)
        case .offline:
            Image(systemName: "wifi.slash")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .help(localized("Could not reach the weather service — showing the last reading."))
        case .ok:
            if let reading = weather.reading {
                Text(reading.tempText)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        case .idle:
            EmptyView()
        }
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.6)
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
            content()
        }
    }

    /// A miniature of the treatment itself, not a name in a dropdown: borders
    /// are visual, so the options must be.
    private func borderSwatch(_ border: Appearance.Border) -> some View {
        Button {
            appearance.border = border
        } label: {
            VStack(spacing: 5) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.black)
                    switch border {
                    case .none:
                        EmptyView()
                    case .hairline:
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .stroke(Color.white.opacity(0.35), lineWidth: 1)
                    case .glow:
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .stroke(appearance.tint, lineWidth: 1.5)
                            .blur(radius: 1.5)
                    case .gradient:
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .stroke(
                                AngularGradient(
                                    colors: [appearance.tint.opacity(0.1), appearance.tint, appearance.tint.opacity(0.1)],
                                    center: .center
                                ),
                                lineWidth: 1.5
                            )
                    }
                }
                .frame(width: 60, height: 26)
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(appearance.border == border ? appearance.tint : .clear, lineWidth: 2)
                        .padding(-3)
                )
                Text(border.title)
                    .font(.system(size: 9))
                    .foregroundStyle(appearance.border == border ? .primary : .secondary)
            }
        }
        .buttonStyle(.plain)
    }

    private func accentSwatch(_ accent: Appearance.Accent) -> some View {
        Button {
            appearance.accent = accent
        } label: {
            ZStack {
                if accent == .artwork {
                    // Not a colour — a behaviour. The swatch says "whatever is
                    // playing" with a note instead of pretending to be a hue.
                    Circle()
                        .fill(
                            AngularGradient(
                                colors: [.blue, .purple, .pink, .orange, .teal, .blue],
                                center: .center
                            )
                        )
                    Image(systemName: "music.note")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                } else {
                    Circle().fill(accent.color)
                }
            }
            .frame(width: 26, height: 26)
            .overlay(
                Circle()
                    .stroke(appearance.accent == accent ? Color.primary : .clear, lineWidth: 2)
                    .padding(-3)
            )
            .help(accent.title)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Preview

    private var preview: some View {
        VStack(spacing: 14) {
            ZStack(alignment: .top) {
                // A stand-in desktop, colourful on purpose: glass and glow are
                // invisible against a flat grey, and that is exactly the doubt
                // this preview exists to remove.
                LinearGradient(
                    colors: [
                        Color(red: 0.16, green: 0.19, blue: 0.42),
                        Color(red: 0.45, green: 0.20, blue: 0.44),
                        Color(red: 0.85, green: 0.44, blue: 0.28),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                miniPanel
                    .padding(.top, 0)
            }
            .frame(width: 300, height: 320)

            Button {
                replay()
            } label: {
                Label(localized("Replay opening"), systemImage: "arrow.counterclockwise")
                    .font(.system(size: 11))
            }
            .controlSize(.small)
        }
        .padding(20)
    }

    /// The panel at one-half scale: same shape, same border view, same springs.
    private var miniPanel: some View {
        let open = previewOpen
        let size = open ? CGSize(width: 250, height: 110) : CGSize(width: 96, height: 20)
        let topR: CGFloat = open ? 10 : 5
        let bottomR: CGFloat = open ? 16 : 7
        let shape = NotchShape(topRadius: topR, bottomRadius: bottomR)
        return ZStack {
            if appearance.usesGlass {
                // In-window this blurs the gradient behind it, which is the same
                // statement the real panel makes against the wallpaper.
                Rectangle().fill(.ultraThinMaterial).clipShape(shape)
            }
            shape.fill(appearance.panelFill)
            PanelBorder(appearance: appearance, topRadius: topR, bottomRadius: bottomR, isOpen: open)
            if open {
                miniContent
                    .transition(.opacity)
            } else {
                HStack {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(appearance.tint.opacity(0.8))
                        .frame(width: 12, height: 12)
                    Spacer()
                    EqualizerBars(isAnimating: appearance.allowsPerpetualMotion, color: appearance.tint)
                }
                .padding(.horizontal, 8)
                .transition(.opacity)
            }
        }
        .frame(width: size.width + 2 * topR, height: size.height)
        .animation(appearance.openAnimation, value: previewOpen)
    }

    private var miniContent: some View {
        HStack(spacing: 10) {
            VStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(i == 0 ? Color.white.opacity(0.18) : Color.white.opacity(0.08))
                        .frame(width: 18, height: 15)
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 3).fill(appearance.tint.opacity(0.75)).frame(width: 90, height: 8)
                RoundedRectangle(cornerRadius: 3).fill(Color.white.opacity(0.25)).frame(width: 130, height: 6)
                RoundedRectangle(cornerRadius: 3).fill(Color.white.opacity(0.14)).frame(width: 70, height: 6)
                Spacer(minLength: 0)
                Capsule().fill(Color.white.opacity(0.2)).frame(width: 140, height: 3)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .padding(.top, 6)
    }

    private func replay() {
        previewOpen = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            previewOpen = true
        }
    }
}
