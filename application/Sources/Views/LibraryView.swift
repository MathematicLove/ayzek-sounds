import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @ObservedObject var library: LibraryStore
    @ObservedObject var player: AudioEngine
    @Binding var search: String
    @Binding var sortOrder: LibrarySortOrder

    @State private var showingImporter = false
    @State private var editingTrack: Track?
    @State private var trackPendingDelete: Track?

    var filteredTracks: [Track] {
        let q = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let base = q.isEmpty ? library.tracks : library.tracks.filter {
            $0.title.lowercased().contains(q) || $0.displayArtist.lowercased().contains(q)
        }
        return sortOrder.sort(base)
    }

    var body: some View {
        List {
            if search.isEmpty, !library.recentTracks.isEmpty {
                Section("Недавно проигрывали") {
                    ForEach(library.recentTracks) { track in
                        row(for: track)
                    }
                    Button(role: .destructive) {
                        library.clearRecents()
                    } label: {
                        Label("Очистить недавние", systemImage: "trash")
                    }
                }
            }

            Section(library.tracks.isEmpty ? "" : "Все треки (\(filteredTracks.count))") {
                if library.tracks.isEmpty {
                    emptyState
                } else if filteredTracks.isEmpty {
                    Text("Ничего не найдено").foregroundStyle(.secondary)
                } else {
                    ForEach(filteredTracks) { track in
                        row(for: track)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .searchable(text: $search, prompt: "Поиск по трекам")
        .navigationTitle("Ayzek Sounds")
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Menu {
                    Picker("Сортировка", selection: $sortOrder) {
                        ForEach(LibrarySortOrder.allCases) { order in
                            Text(order.rawValue).tag(order)
                        }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down.circle")
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { showingImporter = true } label: {
                    if library.isImporting {
                        ProgressView()
                    } else {
                        Image(systemName: "plus.circle.fill")
                    }
                }
                .disabled(library.isImporting)
            }
        }
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [.mp3, .audio],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls): library.add(urls: urls)
            case .failure(let error): print("Importer error: \(error)")
            }
        }
        .sheet(item: $editingTrack) { track in
            EditTrackSheet(track: track, player: player, library: library)
        }
        .alert("Удалить трек?", isPresented: Binding(
            get: { trackPendingDelete != nil },
            set: { if !$0 { trackPendingDelete = nil } }
        ), presenting: trackPendingDelete) { track in
            Button("Удалить", role: .destructive) {
                if player.currentTrack?.id == track.id { player.stop() }
                library.remove(track: track)
            }
            Button("Отмена", role: .cancel) {}
        } message: { track in
            Text("«\(track.title)» будет удалён из библиотеки без возможности восстановления.")
        }
    }

    private func row(for track: Track) -> some View {
        TrackRow(track: track, library: library,
                  isCurrent: player.currentTrack?.id == track.id,
                  isPlaying: player.currentTrack?.id == track.id && player.state == .playing)
            .onTapGesture {
                if player.currentTrack?.id == track.id {
                    player.togglePlayPause()
                } else {
                    player.load(track: track, library: library)
                    player.play()
                }
            }
            .swipeActions(edge: .trailing) {
                Button(role: .destructive) { trackPendingDelete = track } label: {
                    Label("Удалить", systemImage: "trash")
                }
            }
            .swipeActions(edge: .leading) {
                Button { editingTrack = track } label: {
                    Label("Изменить", systemImage: "pencil")
                }
                .tint(.accentColor)
            }
            .contextMenu {
                Button { editingTrack = track } label: {
                    Label("Изменить", systemImage: "pencil")
                }
                Button(role: .destructive) { trackPendingDelete = track } label: {
                    Label("Удалить", systemImage: "trash")
                }
            }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "music.note.list")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("Библиотека пуста")
                .font(.headline)
            Text("Нажмите «+», чтобы добавить аудиофайлы с устройства.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .listRowBackground(Color.clear)
    }
}
