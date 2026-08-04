import SwiftUI

struct ShelfPane: View {
    @ObservedObject var shelf: ShelfStore
    var isTargeted: Bool

    var body: some View {
        VStack(spacing: 0) {
            if shelf.items.isEmpty {
                dropHint
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(shelf.items) { item in
                            ShelfCard(item: item, shelf: shelf)
                        }
                    }
                    .padding(.horizontal, 2)
                    .frame(maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                footer
            }
        }
        .padding(.top, 2)
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
                VStack(spacing: 7) {
                    Image(systemName: "tray.and.arrow.down.fill")
                        .font(.system(size: 20, weight: .light))
                        .foregroundStyle(isTargeted ? .white : Theme.tertiary)
                    Text("Перетащи файлы в челку")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.secondary)
                    Text("Они полежат здесь, пока не понадобятся")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.tertiary)
                }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(Theme.contentAnimation, value: isTargeted)
    }

    private var footer: some View {
        HStack {
            Text("Тяни карточку наружу, чтобы переместить файл")
                .font(.system(size: 9))
                .foregroundStyle(Theme.tertiary)
            Spacer()
            Button("Очистить") { shelf.clear() }
                .buttonStyle(.plain)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Theme.secondary)
        }
        .padding(.top, 2)
    }
}

private struct ShelfCard: View {
    let item: ShelfItem
    @ObservedObject var shelf: ShelfStore
    @State private var hovering = false

    var body: some View {
        VStack(spacing: 6) {
            Image(nsImage: item.icon)
                .resizable()
                .frame(width: 38, height: 38)
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
                .fill(hovering ? Theme.surfaceHover : Theme.surface)
        )
        .overlay(alignment: .topTrailing) {
            if hovering {
                Button { shelf.remove(item) } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.white.opacity(0.75))
                }
                .buttonStyle(.plain)
                .padding(4)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onHover { hovering = $0 }
        .onTapGesture(count: 2) { shelf.open(item) }
        .contextMenu {
            Button("Открыть") { shelf.open(item) }
            Button("Показать в Finder") { shelf.reveal(item) }
            Divider()
            Button("Убрать с полки") { shelf.remove(item) }
        }
        .onDrag {
            NSItemProvider(contentsOf: item.url) ?? NSItemProvider()
        }
        .animation(Theme.contentAnimation, value: hovering)
    }
}
