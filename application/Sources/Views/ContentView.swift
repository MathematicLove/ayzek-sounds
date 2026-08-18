import SwiftUI
import AVFoundation

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase

    @StateObject private var library = LibraryStore()
    @StateObject private var equalizer = EqualizerStore()
    @StateObject private var player: AudioEngine
    @State private var search = ""
    @State private var sortOrder: LibrarySortOrder = .dateAddedDesc
    @State private var showingNowPlaying = false

    init() {
        let eqStore = EqualizerStore()
        _equalizer = StateObject(wrappedValue: eqStore)
        _player = StateObject(wrappedValue: AudioEngine(equalizerStore: eqStore))
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                LibraryView(library: library, player: player, search: $search, sortOrder: $sortOrder)

                if player.currentTrack != nil {
                    MiniPlayerBar(player: player, library: library) {
                        showingNowPlaying = true
                    }
                }
            }
        }
        .navigationViewStyle(.stack)
        .sheet(isPresented: $showingNowPlaying) {
            NowPlayingView(player: player, library: library, equalizer: equalizer)
        }
        .onAppear {
            player.libraryProvider = { [weak library] in library }
            player.playOrderProvider = { [weak library] in
                guard let library else { return [] }
                return sortOrder.sort(library.tracks)
            }
        }
        .onChange(of: scenePhase) { newPhase in
            if newPhase == .active {
                do { try AVAudioSession.sharedInstance().setActive(true, options: []) } catch {}
            }
        }
    }
}
