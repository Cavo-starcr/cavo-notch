import SwiftUI

struct SnippetsPane: View {
    @ObservedObject var snippets: SnippetStore
    /// Whether the panel holds the keyboard, so the fields can follow it.
    @Binding var wantsKeyboard: Bool

    /// Which field has the caret. One state for all three, because only one of
    /// them can be typed into at a time and the pane switches between them.
    private enum Field { case search, label, text }

    @FocusState private var focused: Field?
    @State private var isAdding = false
    @State private var draftLabel = ""
    @State private var draftText = ""

    var body: some View {
        VStack(spacing: 6) {
            if isAdding { editor } else { search }
            list
        }
        .padding(.top, 2)
        .onAppear { focused = wantsKeyboard ? .search : nil }
        .onChange(of: wantsKeyboard) { _, wants in
            guard !wants else {
                focused = isAdding ? .text : .search
                return
            }
            focused = nil
        }
        .animation(Theme.contentAnimation, value: isAdding)
    }

    // MARK: - Search

    private var search: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Theme.tertiary)
            TextField("", text: $snippets.query)
                .textFieldStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(.white)
                .tint(Theme.secondary)
                .focused($focused, equals: .search)
                .onKeyPress(.escape) {
                    snippets.query = ""
                    return .handled
                }
            if !snippets.query.isEmpty {
                Button { snippets.query = "" } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Theme.secondary)
                }
                .buttonStyle(.plain)
            }
            Button { beginAdding() } label: {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.secondary)
            }
            .buttonStyle(.plain)
            .help(localized("Add a snippet"))
        }
        .padding(.horizontal, 9)
        .frame(height: 24)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Theme.surface)
        )
        .contentShape(Rectangle())
        .onTapGesture { focused = .search }
    }

    // MARK: - Adding

    /// Takes the place of the search row rather than sitting above it: the pane
    /// is two rows tall in a panel that never resizes, and one of the two is
    /// the list.
    private var editor: some View {
        HStack(spacing: 8) {
            TextField(localized("Name"), text: $draftLabel)
                .textFieldStyle(.plain)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white)
                .tint(Theme.secondary)
                .frame(width: 96)
                .focused($focused, equals: .label)
                .onSubmit { commit() }

            Rectangle()
                .fill(Theme.tertiary.opacity(0.4))
                .frame(width: 1, height: 12)

            TextField(localized("Text"), text: $draftText)
                .textFieldStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(.white)
                .tint(Theme.secondary)
                .focused($focused, equals: .text)
                .onSubmit { commit() }

            Button { commit() } label: {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(draftText.isEmpty ? Theme.tertiary : Color.green)
            }
            .buttonStyle(.plain)
            .disabled(draftText.isEmpty)

            Button { cancelAdding() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 9)
        .frame(height: 24)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Theme.surfaceHover)
        )
        // Escape leaves the draft rather than the tab. Caught on the row so it
        // works from either field.
        .onKeyPress(.escape) {
            cancelAdding()
            return .handled
        }
    }

    private func beginAdding() {
        draftLabel = ""
        draftText = ""
        isAdding = true
        wantsKeyboard = true
        // The value is the part that cannot be left out, so the caret starts
        // there; the name is a step back for those who want one.
        focused = .text
    }

    private func cancelAdding() {
        isAdding = false
        draftLabel = ""
        draftText = ""
        focused = .search
    }

    private func commit() {
        guard !draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        snippets.add(label: draftLabel, text: draftText)
        // Straight into another one: adding snippets comes in runs, and the
        // list underneath already shows what has landed.
        draftLabel = ""
        draftText = ""
        focused = .text
    }

    // MARK: - List

    @ViewBuilder
    private var list: some View {
        if snippets.filtered.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: snippets.items.isEmpty ? "pin" : "magnifyingglass")
                    .font(.system(size: 18, weight: .light))
                    .foregroundStyle(Theme.tertiary)
                if snippets.items.isEmpty, !isAdding {
                    Text("Nothing here yet — add with +")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.tertiary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 3) {
                    ForEach(snippets.filtered) { item in
                        SnippetRow(item: item, snippets: snippets)
                    }
                }
                .padding(.bottom, 2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct SnippetRow: View {
    let item: Snippet
    @ObservedObject var snippets: SnippetStore
    @State private var hovering = false
    @State private var justCopied = false

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: justCopied ? "checkmark" : item.symbol)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(justCopied ? Color.green : Theme.tertiary)
                .frame(width: 14)
            if !item.label.isEmpty {
                Text(item.label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .layoutPriority(1)
            }
            Text(item.text.replacingOccurrences(of: "\n", with: " "))
                .font(.system(size: 11))
                .foregroundStyle(item.label.isEmpty ? .white : Theme.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 6)
            // Only under the pointer: a row of crosses would compete with the
            // snippets themselves for a glance.
            if hovering {
                Button { snippets.remove(item) } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Theme.secondary)
                }
                .buttonStyle(.plain)
                .help(localized("Delete"))
            }
        }
        .padding(.horizontal, 9)
        .frame(height: 26)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(hovering ? Theme.surfaceHover : Theme.surface)
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture {
            snippets.copy(item)
            justCopied = true
            // Emptying the search lets go of the panel: nothing is being typed
            // any more, so nothing needs to hold it open.
            snippets.query = ""
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) { justCopied = false }
        }
        .animation(Theme.contentAnimation, value: hovering)
        .animation(Theme.contentAnimation, value: justCopied)
    }
}
