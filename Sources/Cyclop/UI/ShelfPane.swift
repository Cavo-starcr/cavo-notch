import SwiftUI

struct ShelfPane: View {
    @ObservedObject var shelf: ShelfStore
    var isTargeted: Bool

    /// Which card the pointer is over — decided by the pane, not by the cards.
    ///
    /// Per-card `onHover` breaks on the shelf's most repetitive gesture:
    /// deleting cards one after another. Hover events are made of mouse
    /// movement, and when a deleted card's neighbour slides under a pointer
    /// that has not moved, there are no events — the neighbour never learns it
    /// is hovered, its ✕ never appears, and the click meant to delete it
    /// selects it instead, until a stray wiggle of the mouse fixes everything.
    /// So the pane tracks the pointer and every card's frame itself, and
    /// re-decides on either change: the pointer moving, or the cards moving
    /// under it. Scrolling the strip is the same case and heals the same way.
    @State private var hoveredID: UUID?
    @State private var hoverPoint: CGPoint?
    @State private var frames: [UUID: CGRect] = [:]

    var body: some View {
        VStack(spacing: 0) {
            if shelf.items.isEmpty {
                dropHint
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(shelf.items) { item in
                            ShelfCard(item: item, shelf: shelf, isHovered: hoveredID == item.id)
                                .background(
                                    GeometryReader { geo in
                                        Color.clear.preference(
                                            key: CardFramesKey.self,
                                            value: [item.id: geo.frame(in: .named("shelf"))]
                                        )
                                    }
                                )
                        }
                    }
                    .padding(.horizontal, 2)
                    .frame(maxHeight: .infinity)
                }
                .coordinateSpace(name: "shelf")
                .onContinuousHover(coordinateSpace: .named("shelf")) { phase in
                    switch phase {
                    case .active(let point):
                        hoverPoint = point
                        rehit()
                    case .ended:
                        hoverPoint = nil
                        hoveredID = nil
                        shelf.hoveredID = nil
                    }
                }
                .onPreferenceChange(CardFramesKey.self) { new in
                    frames = new
                    rehit()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                footer
            }
        }
        .padding(.top, 2)
    }

    /// Compresses whatever is selected. Any selected card names the same set —
    /// `actionURLs` resolves a card to its selection — so the first one does.
    private func compressSelection() {
        guard let anchor = shelf.items.first(where: { shelf.isSelected($0) }) else { return }
        shelf.compress(anchor)
    }

    /// The one decision both signals feed: which frame holds the last known
    /// pointer position.
    private func rehit() {
        guard let hoverPoint else { return }
        hoveredID = frames.first(where: { $0.value.contains(hoverPoint) })?.key
        // Handed to the store so the space bar knows which card is being looked
        // at. Plain assignment, not a published change — see `ShelfStore`.
        shelf.hoveredID = hoveredID
    }

    private var dropHint: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(
                isTargeted ? Color.white.opacity(0.6) : Theme.hairline,
                style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])
            )
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isTargeted ? Theme.surface : .clear)
            )
            .overlay(
                Image(systemName: "tray.and.arrow.down.fill")
                    .font(.system(size: 20, weight: .light))
                    .foregroundStyle(isTargeted ? .white : Theme.tertiary)
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(Theme.contentAnimation, value: isTargeted)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if !shelf.selection.isEmpty {
                Text(localized("Selected: %d", shelf.selection.count))
                    .font(.system(size: 9))
                    .foregroundStyle(Theme.tertiary)
            }
            // Says where the archive went, because that is the one part of
            // compressing that cannot be seen happening. The card lands on the
            // shelf either way; this names the folder it also landed in.
            if shelf.isCompressing {
                HStack(spacing: 5) {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.7)
                    Text(localized("Compressing…"))
                        .font(.system(size: 9))
                        .foregroundStyle(Theme.tertiary)
                }
            }
            Spacer()
            if !shelf.selection.isEmpty {
                // Zipping a selection from the footer as well as from a card's
                // menu: with several cards picked, the footer is where the eye
                // already is — it is the row that says how many.
                Button(localized("Compress")) { compressSelection() }
                    .buttonStyle(.plain)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(shelf.isCompressing ? Theme.tertiary : Theme.secondary)
                    .disabled(shelf.isCompressing)
                Button("Deselect") { shelf.clearSelection() }
                    .buttonStyle(.plain)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Theme.secondary)
            }
            Button("Clear") { shelf.clear() }
                .buttonStyle(.plain)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Theme.secondary)
        }
        .padding(.top, 2)
    }
}

private struct CardFramesKey: PreferenceKey {
    static let defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

private struct ShelfCard: View {
    let item: ShelfItem
    @ObservedObject var shelf: ShelfStore
    /// Handed down from the pane, which is the one place that can know it
    /// correctly when cards move under a stationary pointer.
    let isHovered: Bool

    /// Non-nil while this card's name is being edited; holds the draft.
    @State private var renaming: String?
    /// The card's own AppKit view, needed as the anchor for the share popover —
    /// `NSSharingServicePicker` is AppKit and wants a rect in a real view.
    @State private var host: NSView?

    private var isSelected: Bool { shelf.isSelected(item) }

    private var renameBinding: Binding<Bool> {
        Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })
    }

    /// One card compresses itself; a selection this card belongs to compresses
    /// as a set, and the title says which is about to happen.
    private var compressTitle: String {
        let count = shelf.actionURLs(startingAt: item).count
        return count > 1 ? localized("Compress %d Items", count) : localized("Compress")
    }

    private func share() {
        guard let host else { return }
        shelf.share(item, from: host, rect: host.bounds)
    }

    var body: some View {
        VStack(spacing: 6) {
            // Fit, not fill: a screenshot is landscape and a file icon is
            // square, and forcing either into the other's box is what squashed
            // the wide ones. The box is wide enough for a 16:10 frame, so a
            // square icon simply centres in it.
            Image(nsImage: item.icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 68, height: 40)
            Text(item.name)
                .font(.system(size: 9))
                .foregroundStyle(Theme.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(height: 24, alignment: .top)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 8)
        .frame(width: 86, height: 92)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isSelected ? Color.white.opacity(0.18) : (isHovered ? Theme.surfaceHover : Theme.surface))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(isSelected ? 0.55 : 0), lineWidth: 1.5)
                .allowsHitTesting(false)
        )
        // Owns clicks and drags: a group drag needs one dragging item per file,
        // which SwiftUI's onDrag cannot express. It must stay *below* the close
        // button, otherwise it swallows every click aimed at it.
        .overlay(
            ShelfDragSource(
                urls: { shelf.dragURLs(startingAt: item) },
                onClick: { modifiers in shelf.select(item, modifiers: modifiers) },
                onDoubleClick: { shelf.open(item) }
            )
        )
        .overlay(alignment: .topLeading) {
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.white)
                    .padding(4)
                    .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .topTrailing) {
            if isHovered {
                Button { shelf.remove(item) } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.white.opacity(0.75))
                }
                .buttonStyle(.plain)
                .padding(4)
            }
        }
        // Quick Look is a button rather than the space bar it is everywhere else:
        // the panel only takes the keyboard on the tabs that are typed into, and
        // claiming it for the shelf would dim the caret of whatever the person is
        // actually working in every time the pointer crossed the notch. The
        // preview is one press either way.
        .overlay(alignment: .bottomTrailing) {
            if isHovered {
                Button { shelf.preview(item) } label: {
                    Image(systemName: "eye.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.white.opacity(0.75))
                }
                .buttonStyle(.plain)
                .padding(4)
                .help(localized("Quick Look"))
            }
        }
        // Invisible, and only here to be an anchor: the share sheet is AppKit and
        // needs a real view with a real rect to point at.
        .background(HostView { host = $0 })
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contextMenu {
            Button("Quick Look") { shelf.preview(item) }
            Button("Open") { shelf.open(item) }
            Button("Show in Finder") { shelf.reveal(item) }
            Divider()
            Button("Copy") { shelf.copy(item) }
            Button("Copy Path") { shelf.copyPath(item) }
            // Named by what it will produce rather than by the verb: with three
            // cards selected, "Compress" alone does not say whether the answer
            // is one archive or three.
            Button(compressTitle) { shelf.compress(item) }
                .disabled(shelf.isCompressing)
            Button("Share…") { share() }
            Divider()
            Button("Rename…") { renaming = item.name }
            Button("Remove from Shelf") { shelf.remove(item) }
        }
        // Renaming happens in the pane, not in a window: the panel is already a
        // borderless thing over the menu bar, and a modal sheet has nothing to
        // hang from.
        .popover(isPresented: renameBinding, arrowEdge: .bottom) {
            RenameField(name: renaming ?? item.name) { newName in
                let ok = shelf.rename(item, to: newName)
                renaming = nil
                return ok
            }
        }
        .animation(Theme.contentAnimation, value: isHovered)
        .animation(Theme.contentAnimation, value: isSelected)
    }
}

/// Reports the AppKit view backing a SwiftUI subtree.
///
/// Only exists because `NSSharingServicePicker` predates SwiftUI and takes a
/// view plus a rect rather than a SwiftUI anchor. Draws nothing, hit-tests
/// nothing, and hands the view up once.
private struct HostView: NSViewRepresentable {
    let found: (NSView) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = PassthroughView()
        // The view is inside the card, so a subview that accepted clicks would
        // sit between the card and its drag source.
        DispatchQueue.main.async { found(view) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class PassthroughView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}

/// The rename popover: a field, and Enter to commit.
///
/// Refuses rather than closes when the name is taken or invalid — `ShelfStore`
/// decides, and the field stays open with the draft intact so the next attempt
/// starts from what was typed instead of from the old name.
private struct RenameField: View {
    @State var name: String
    /// Returns whether the rename went through.
    let commit: (String) -> Bool

    @State private var rejected = false
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            TextField("", text: $name)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .frame(width: 220)
                .focused($focused)
                .onSubmit { attempt() }
                .onChange(of: name) { rejected = false }
            Button(localized("Rename")) { attempt() }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white)
        }
        .padding(10)
        .overlay(alignment: .bottomLeading) {
            if rejected {
                Text(localized("That name is taken or not allowed"))
                    .font(.system(size: 9))
                    .foregroundStyle(Color(red: 1, green: 0.55, blue: 0.5))
                    .padding(.leading, 10)
                    .padding(.bottom, -4)
            }
        }
        // The popover is its own window and does become key, so unlike the panel
        // it can simply take the field.
        .onAppear { focused = true }
    }

    private func attempt() {
        if !commit(name) { rejected = true }
    }
}
