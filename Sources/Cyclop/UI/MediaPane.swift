import SwiftUI

struct MediaPane: View {
    @ObservedObject var media: MediaController

    var body: some View {
        if let track = media.track {
            HStack(spacing: 16) {
                artwork
                VStack(alignment: .leading, spacing: 0) {
                    Text(track.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text([track.artist, track.album].filter { !$0.isEmpty }.joined(separator: " — "))
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.secondary)
                        .lineLimit(1)
                        .padding(.top, 3)

                    Spacer(minLength: 8)
                    scrubber
                    Spacer(minLength: 8)
                    controls
                }
            }
            .padding(.top, 4)
        } else {
            emptyState
        }
    }

    // MARK: - Pieces

    private var artwork: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Theme.surface)
            if let image = media.artwork {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: "music.note")
                    .font(.system(size: 26, weight: .light))
                    .foregroundStyle(Theme.tertiary)
            }
        }
        .frame(width: 116, height: 116)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Theme.hairline, lineWidth: 1)
        )
    }

    private var scrubber: some View {
        VStack(spacing: 5) {
            GeometryReader { geo in
                let progress = media.duration > 0 ? media.position / media.duration : 0
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.surface)
                    Capsule()
                        .fill(Color.white.opacity(0.85))
                        .frame(width: max(0, min(1, progress)) * geo.size.width)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0).onEnded { value in
                        guard geo.size.width > 0 else { return }
                        media.seek(to: media.duration * (value.location.x / geo.size.width))
                    }
                )
            }
            .frame(height: 4)

            HStack {
                Text(formatTime(media.position))
                Spacer()
                Text(formatTime(media.duration))
            }
            .font(.system(size: 9, weight: .medium).monospacedDigit())
            .foregroundStyle(Theme.tertiary)
        }
    }

    private var controls: some View {
        HStack(spacing: 8) {
            Button { media.previous() } label: { Image(systemName: "backward.fill") }
                .buttonStyle(NotchButtonStyle())
            Button { media.togglePlayPause() } label: {
                Image(systemName: media.isPlaying ? "pause.fill" : "play.fill")
            }
            .buttonStyle(NotchButtonStyle(size: 34, prominent: true))
            Button { media.next() } label: { Image(systemName: "forward.fill") }
                .buttonStyle(NotchButtonStyle())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "music.note.list")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(Theme.tertiary)
            Text("Ничего не играет")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.secondary)
            Text("Запусти Apple Music или Spotify — трек появится здесь.")
                .font(.system(size: 10))
                .foregroundStyle(Theme.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
