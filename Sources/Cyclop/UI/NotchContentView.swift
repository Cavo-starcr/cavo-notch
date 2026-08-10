import SwiftUI

struct NotchContentView: View {
    @ObservedObject var vm: NotchViewModel
    @ObservedObject private var appearance = Appearance.shared

    private var isOpen: Bool { vm.isOpen || vm.isDropTargeted }
    private var size: CGSize { vm.bodySize }
    private var topRadius: CGFloat { isOpen ? Theme.openTopRadius : Theme.collapsedTopRadius }

    var body: some View {
        // The shape is wider than the body by `topRadius` on each side: that
        // slack is where the concave shoulders live, so it must not be clipped.
        ZStack(alignment: .top) {
            panelBody
                .frame(width: size.width + 2 * topRadius, height: size.height)
                .shadow(
                    color: .black.opacity(isOpen ? 0.5 : (vm.musicStripActive ? 0.35 : 0)),
                    radius: appearance.shadowRadius(open: isOpen),
                    y: 8
                )

            VStack(spacing: 0) {
                header
                if isOpen {
                    content
                        .transition(.opacity)
                }
            }
            .frame(width: size.width, height: size.height, alignment: .top)
            .clipped()
        }
        .frame(width: size.width + 2 * topRadius, height: size.height, alignment: .top)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(Theme.openAnimation, value: isOpen)
        .animation(Theme.paneAnimation, value: vm.tab)
    }

    /// The black shape, its material and its outline. The glass variant blurs
    /// the wallpaper through the window; the border is whatever `Appearance`
    /// says it is, and both apply to the collapsed strip as much as the panel.
    private var panelBody: some View {
        let bottomRadius = isOpen ? Theme.openBottomRadius : Theme.collapsedBottomRadius
        let shape = NotchShape(topRadius: topRadius, bottomRadius: bottomRadius)
        return ZStack {
            if appearance.usesGlass {
                BehindWindowBlur().clipShape(shape)
            }
            shape.fill(appearance.panelFill)
            PanelBorder(
                appearance: appearance,
                topRadius: topRadius,
                bottomRadius: bottomRadius,
                isOpen: isOpen
            )
        }
    }

    // MARK: - Header
    //
    // This strip sits directly on top of the menu bar. Menu bar utilities such
    // as Ice watch for clicks there with a global event monitor — a passive
    // observer that sees the click no matter which window consumes it — so
    // clicking here toggles them as a side effect. Nothing interactive goes in
    // this row; the tab switcher lives in the rail below.

    private var header: some View {
        HStack(spacing: 0) {
            if isOpen {
                Text(vm.tab.title.uppercased())
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(Theme.tertiary)
                    .padding(.leading, 16)
                    .id(vm.tab)
                    .transition(.opacity)
            } else if vm.musicStripActive {
                // The Dynamic Island move: artwork on one wing of the notch,
                // level meter on the other, and the physical cutout untouched
                // between them. No title — at this size a name is clutter, and
                // the artwork *is* the identity of what is playing.
                artworkThumb
                    .padding(.leading, 9)
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
            Spacer(minLength: 0)
            Color.clear.frame(width: vm.geometry.notchSize.width, height: 1)
            Spacer(minLength: 0)
            if isOpen {
                trailing
                    .padding(.trailing, 16)
                    .transition(.opacity)
            } else if vm.musicStripActive {
                EqualizerBars(isAnimating: vm.media.isPlaying && appearance.allowsPerpetualMotion, color: appearance.tint)
                    .padding(.trailing, 12)
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
        }
        .frame(height: vm.geometry.notchSize.height)
        .animation(Theme.openAnimation, value: vm.musicStripActive)
    }

    private var artworkThumb: some View {
        Group {
            if let artwork = vm.media.artwork {
                Image(nsImage: artwork)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Theme.surface)
                    .overlay(
                        Image(systemName: "music.note")
                            .font(.system(size: 8))
                            .foregroundStyle(Theme.tertiary)
                    )
            }
        }
        .frame(width: 17, height: 17)
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        // Track identity change, not every artwork byte: the crossfade should
        // fire when the song changes, not when the same art re-decodes.
        .id(vm.media.track?.key)
    }

    @ViewBuilder
    private var trailing: some View {
        switch vm.tab {
        case .media:
            HStack(spacing: 6) {
                if vm.media.track != nil {
                    EqualizerBars(isAnimating: vm.media.isPlaying)
                }
                Text(vm.media.sourceName ?? "")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Theme.tertiary)
            }
        case .shelf:
            counter(vm.shelf.items.count)
        case .clipboard:
            counter(vm.clipboard.items.count)
        case .snippets:
            counter(vm.snippets.items.count)
        case .calendar:
            if let next = vm.calendar.next {
                Text(CalendarPane.countdown(to: next, from: vm.calendar.now))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(next.isRunning ? Color.white.opacity(0.8) : Theme.tertiary)
            }
        case .translate:
            // Nothing: the columns name both languages already, and the strip
            // is the one part of the panel worth not spending on a repeat.
            EmptyView()
        case .notes:
            NotesCounter(notes: vm.notes)
        case .timer:
            TimerCounter(timer: vm.timer)
        }
    }

    @ViewBuilder
    private func counter(_ value: Int) -> some View {
        if value > 0 {
            Text("\(value)")
                .font(.system(size: 10, weight: .medium).monospacedDigit())
                .foregroundStyle(Theme.tertiary)
        }
    }

    // MARK: - Body

    /// One namespace across both rails, so the selection pill slides between
    /// columns as well as within one.
    @Namespace private var railSelection

    private var content: some View {
        HStack(spacing: 14) {
            Rail(vm: vm, tabs: NotchViewModel.Tab.leftRail, selection: railSelection)
            panes
            Rail(vm: vm, tabs: NotchViewModel.Tab.rightRail, selection: railSelection)
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var panes: some View {
        // Content is replaced in place — no travel. The rail is vertical and
        // the panes are unrelated, so a direction would only be decoration.
        ZStack {
            pane
                .id(vm.tab)
                .transition(.asymmetric(
                    insertion: .opacity
                        .combined(with: .scale(scale: 0.97))
                        .animation(Theme.paneIn),
                    removal: .opacity
                        .combined(with: .scale(scale: 1.02))
                        .animation(Theme.paneOut)
                ))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }

    @ViewBuilder
    private var pane: some View {
        switch vm.tab {
        case .media:
            MediaPane(media: vm.media)
        case .shelf:
            ShelfPane(shelf: vm.shelf, isTargeted: vm.isDropTargeted)
        case .clipboard:
            ClipboardPane(clipboard: vm.clipboard, privacy: vm.privacy)
        case .calendar:
            CalendarPane(calendar: vm.calendar, privacy: vm.privacy)
        case .snippets:
            SnippetsPane(snippets: vm.snippets, privacy: vm.privacy, wantsKeyboard: $vm.wantsKeyboard)
        case .translate:
            TranslatePane(translator: vm.translator, wantsKeyboard: $vm.wantsKeyboard)
        case .notes:
            NotesPane(notes: vm.notes, privacy: vm.privacy, wantsKeyboard: $vm.wantsKeyboard)
        case .timer:
            TimerPane(timer: vm.timer)
        }
    }
}

/// Watches the note store itself rather than reading through the view model:
/// notes are born and deleted inside the pane while this counter is on
/// screen, and the view model deliberately does not forward keystroke-driven
/// stores.
private struct NotesCounter: View {
    @ObservedObject var notes: NoteStore

    var body: some View {
        if !notes.notes.isEmpty {
            Text("\(notes.notes.count)")
                .font(.system(size: 10, weight: .medium).monospacedDigit())
                .foregroundStyle(Theme.tertiary)
        }
    }
}

/// Tab switcher.
///
/// Hovering switches tabs, but only after the pointer has stopped: a pointer
/// crossing the rail on its way somewhere else is gone in a few dozen
/// milliseconds, while one that came to choose stays put. The same dwell
/// threshold is what separates "the mouse was flung across the top of the
/// screen" from "the mouse came to the notch" in `PointerWatcher`.
private struct Rail: View {
    @ObservedObject var vm: NotchViewModel
    /// Which icons this rail carries — there are two rails now, one per side.
    let tabs: [NotchViewModel.Tab]
    /// Shared with the other rail, so there is exactly one pill in the world.
    let selection: Namespace.ID

    @State private var hovered: NotchViewModel.Tab?

    /// Long enough to swallow a pass-through, short enough that a deliberate
    /// hover still feels like it answered instantly.
    private let dwell = Duration.milliseconds(150)

    var body: some View {
        VStack(spacing: 4) {
            ForEach(tabs) { tab in
                Button {
                    vm.select(tab)
                } label: {
                    Image(systemName: tab.symbol)
                        .font(.system(size: 12, weight: .medium))
                        .frame(width: 30, height: 24)
                        .background {
                            // The selection is one pill that travels, not a
                            // highlight that blinks out here and in there:
                            // matched geometry turns the switch into movement,
                            // and movement is what says "same thing, new place".
                            if vm.tab == tab {
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(Theme.tint.opacity(0.24))
                                    .matchedGeometryEffect(id: "rail.selection", in: selection)
                            } else if hovered == tab {
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(Theme.surface)
                            }
                        }
                        .foregroundStyle(vm.tab == tab ? Color.white : Theme.tertiary)
                        .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                        // A render-time transform. Growing the frame instead
                        // would re-lay out the rail on every hover, and layout
                        // that runs on pointer movement is exactly the kind
                        // that shows up as a stutter.
                        .scaleEffect(hovered == tab ? 1.15 : 1)
                }
                .buttonStyle(.plain)
                .onHover { inside in
                    if inside {
                        hovered = tab
                    } else if hovered == tab {
                        hovered = nil
                    }
                }
            }
        }
        .frame(width: 30)
        .frame(maxHeight: .infinity, alignment: .center)
        .animation(Theme.contentAnimation, value: hovered)
        .animation(Theme.openAnimation, value: vm.tab)
        // Moving to another icon cancels the pending switch along with the
        // task, so only the icon actually rested on ever wins.
        .task(id: hovered) {
            guard let hovered, hovered != vm.tab else { return }
            try? await Task.sleep(for: dwell)
            guard !Task.isCancelled else { return }
            vm.select(hovered)
        }
    }

}
