import SwiftUI

/// Lets the user fix a track's title/artist and set a custom artwork URL.
struct EditTrackSheet: View {
    let track: Track
    @ObservedObject var player: AudioEngine
    @ObservedObject var library: LibraryStore
    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var artist: String
    @State private var artworkURL: String

    init(track: Track, player: AudioEngine, library: LibraryStore) {
        self.track = track
        self.player = player
        self.library = library
        _title = State(initialValue: track.title)
        _artist = State(initialValue: track.artist ?? "")
        _artworkURL = State(initialValue: track.artworkURLString ?? "")
    }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Название и исполнитель")) {
                    TextField("Название", text: $title)
                    TextField("Исполнитель", text: $artist)
                }
                Section(header: Text("Обложка (URL)"), footer: Text("Используется, если в файле нет встроенной обложки.")) {
                    TextField("https://…", text: $artworkURL)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .disableAutocorrection(true)
                }
            }
            .navigationTitle("Изменить трек")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Сохранить") { save() }
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func save() {
        var updated = track
        updated.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedArtist = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.artist = trimmedArtist.isEmpty ? nil : trimmedArtist
        let trimmedURL = artworkURL.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.artworkURLString = trimmedURL.isEmpty ? nil : trimmedURL

        library.update(updated)
        if player.currentTrack?.id == updated.id {
            player.currentTrack = updated
            player.updateNowPlayingInfo(forceArtworkReload: true, library: library)
        }
        dismiss()
    }
}
