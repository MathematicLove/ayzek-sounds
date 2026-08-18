import SwiftUI

/// Persistent bottom bar shown whenever a track is loaded; tapping it opens the full player.
struct MiniPlayerBar: View {
    @ObservedObject var player: AudioEngine
    @ObservedObject var library: LibraryStore
    let onTap: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ProgressView(value: player.duration > 0 ? player.currentTime / player.duration : 0)
                .progressViewStyle(.linear)
                .tint(.accentColor)
                .frame(height: 2)

            HStack(spacing: 12) {
                ArtworkView(track: player.currentTrack, library: library, cornerRadius: 6)
                    .frame(width: 40, height: 40)

                VStack(alignment: .leading, spacing: 1) {
                    Text(player.currentTrack?.title ?? "")
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                    Text(player.currentTrack?.displayArtist ?? "")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Button(action: player.playPrevious) {
                    Image(systemName: "backward.fill")
                }
                Button(action: player.togglePlayPause) {
                    Image(systemName: player.state == .playing ? "pause.fill" : "play.fill")
                        .font(.title3)
                }
                Button(action: player.playNext) {
                    Image(systemName: "forward.fill")
                }
            }
            .font(.body)
            .foregroundStyle(.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(.regularMaterial)
        .overlay(Divider(), alignment: .top)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }
}
