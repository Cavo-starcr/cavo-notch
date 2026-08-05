import SwiftUI

struct SnippetsPane: View {
    @ObservedObject var snippets: SnippetStore
    /// Whether the panel holds the keyboard, so the search field can follow it.
    @Binding var wantsKeyboard: Bool

    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 6) {
            search
            list
        }
        .padding(.top, 2)
        .onAppear { focused = wantsKeyboard }
        .onChange(of: wantsKeyboard) { _, wants in focused = wants }
    }

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
                .focused($focused)
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
        }
        .padding(.horizontal, 9)
        .frame(height: 24)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Theme.surface)
        )
        .contentShape(Rectangle())
        .onTapGesture { focused = true }
    }

    @ViewBuilder
    private var list: some View {
        if snippets.filtered.isEmpty {
            Image(systemName: snippets.items.isEmpty ? "pin" : "magnifyingglass")
                .font(.system(size: 18, weight: .light))
                .foregroundStyle(Theme.tertiary)
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
