import SwiftUI

struct NotchContentView: View {
    @ObservedObject var vm: NotchViewModel

    private var isOpen: Bool { vm.isOpen || vm.isDropTargeted }
    private var size: CGSize { vm.bodySize }
    private var topRadius: CGFloat { isOpen ? Theme.openTopRadius : Theme.collapsedTopRadius }

    var body: some View {
        // The shape is wider than the body by `topRadius` on each side: that
        // slack is where the concave shoulders live, so it must not be clipped.
        ZStack(alignment: .top) {
            NotchShape(
                topRadius: topRadius,
                bottomRadius: isOpen ? Theme.openBottomRadius : Theme.collapsedBottomRadius
            )
            .fill(Color.black)
            .frame(width: size.width + 2 * topRadius, height: size.height)
            .shadow(color: .black.opacity(isOpen ? 0.5 : 0), radius: 18, y: 8)

            VStack(spacing: 0) {
                header
                if isOpen {
                    content
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .frame(width: size.width, height: size.height, alignment: .top)
            .clipped()
        }
        .frame(width: size.width + 2 * topRadius, height: size.height, alignment: .top)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(Theme.openAnimation, value: isOpen)
        .animation(Theme.contentAnimation, value: vm.tab)
    }

    // MARK: - Header, split by the physical notch

    private var header: some View {
        HStack(spacing: 0) {
            if isOpen {
                tabs
                    .padding(.leading, 14)
                    .transition(.opacity)
            }
            Spacer(minLength: 0)
            Color.clear.frame(width: vm.geometry.notchSize.width, height: 1)
            Spacer(minLength: 0)
            if isOpen {
                trailing
                    .padding(.trailing, 16)
                    .transition(.opacity)
            }
        }
        .frame(height: vm.geometry.notchSize.height)
    }

    private var tabs: some View {
        HStack(spacing: 2) {
            ForEach(NotchViewModel.Tab.allCases) { tab in
                Button {
                    vm.tab = tab
                } label: {
                    Image(systemName: tab.symbol)
                        .font(.system(size: 11, weight: .medium))
                        .frame(width: 26, height: 20)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(vm.tab == tab ? Theme.surfaceHover : .clear)
                        )
                        .foregroundStyle(vm.tab == tab ? Color.white : Theme.tertiary)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(tab.title)
            }
        }
    }

    @ViewBuilder
    private var trailing: some View {
        switch vm.tab {
        case .media:
            Text(vm.media.sourceName ?? "")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Theme.tertiary)
        case .shelf:
            Text(vm.shelf.items.isEmpty ? "" : "\(vm.shelf.items.count)")
                .font(.system(size: 10, weight: .medium).monospacedDigit())
                .foregroundStyle(Theme.tertiary)
        case .clipboard:
            Text(vm.clipboard.items.isEmpty ? "" : "\(vm.clipboard.items.count)")
                .font(.system(size: 10, weight: .medium).monospacedDigit())
                .foregroundStyle(Theme.tertiary)
        }
    }

    // MARK: - Body

    @ViewBuilder
    private var content: some View {
        Group {
            switch vm.tab {
            case .media:
                MediaPane(media: vm.media)
            case .shelf:
                ShelfPane(shelf: vm.shelf, isTargeted: vm.isDropTargeted)
            case .clipboard:
                ClipboardPane(clipboard: vm.clipboard)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 18)
        .padding(.bottom, 14)
    }
}
