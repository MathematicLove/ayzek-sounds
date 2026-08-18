import SwiftUI

/// Shows local artwork first, then a remote URL override, then a stylised placeholder.
struct ArtworkView: View {
    let localURL: URL?
    let remoteURLString: String?
    var cornerRadius: CGFloat = 8

    init(track: Track?, library: LibraryStore?, cornerRadius: CGFloat = 8) {
        self.localURL = track.flatMap { library?.artworkURL(for: $0) }
        self.remoteURLString = track?.artworkURLString
        self.cornerRadius = cornerRadius
    }

    var body: some View {
        Group {
            if let localURL, let data = try? Data(contentsOf: localURL), let ui = UIImage(data: data) {
                Image(uiImage: ui).resizable().scaledToFill()
            } else if let s = remoteURLString, let url = URL(string: s) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty: placeholder.overlay(ProgressView())
                    case .success(let image): image.resizable().scaledToFill()
                    case .failure: placeholder
                    @unknown default: placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(colors: [Color.accentColor.opacity(0.55), Color.accentColor.opacity(0.15)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Image(systemName: "music.note")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
        }
    }
}
