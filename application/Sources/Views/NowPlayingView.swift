import SwiftUI
import AVKit

/// Full-screen "now playing" experience: big artwork, scrubber, transport, EQ & speed access.
struct NowPlayingView: View {
    @ObservedObject var player: AudioEngine
    @ObservedObject var library: LibraryStore
    @ObservedObject var equalizer: EqualizerStore
    @Environment(\.dismiss) private var dismiss

    @State private var isScrubbing = false
    @State private var scrubValue: Double = 0
    @State private var showingEqualizer = false
    @State private var showingEditTrack = false

    var body: some View {
        NavigationView {
            GeometryReader { geo in
                VStack(spacing: 20) {
                    ArtworkView(track: player.currentTrack, library: library, cornerRadius: 20)
                        .frame(width: min(geo.size.width - 64, 340), height: min(geo.size.width - 64, 340))
                        .shadow(color: .black.opacity(0.25), radius: 20, y: 10)
                        .padding(.top, 12)

                    VStack(spacing: 4) {
                        Text(player.currentTrack?.title ?? "Ничего не выбрано")
                            .font(.title3.weight(.semibold))
                            .lineLimit(1)
                        Text(player.currentTrack?.displayArtist ?? "")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .overlay(alignment: .trailing) {
                        Button { showingEditTrack = true } label: {
                            Image(systemName: "pencil.circle")
                                .font(.title3)
                        }
                        .disabled(player.currentTrack == nil)
                        .padding(.trailing, 24)
                    }

                    VStack(spacing: 4) {
                        Slider(value: Binding(
                            get: { isScrubbing ? scrubValue : player.currentTime },
                            set: { scrubValue = $0 }
                        ), in: 0...(max(player.duration, 0.0001)), onEditingChanged: { editing in
                            isScrubbing = editing
                            if !editing { player.seek(to: scrubValue) }
                        })
                        HStack {
                            Text(timeString(isScrubbing ? scrubValue : player.currentTime))
                            Spacer()
                            Text("-" + timeString(max(0, player.duration - (isScrubbing ? scrubValue : player.currentTime))))
                        }
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 24)

                    HStack(spacing: 34) {
                        Button {
                            player.shuffleEnabled.toggle()
                        } label: {
                            Image(systemName: "shuffle")
                                .foregroundStyle(player.shuffleEnabled ? Color.accentColor : .primary)
                        }

                        Button(action: player.playPrevious) {
                            Image(systemName: "backward.fill").font(.title2)
                        }

                        Button(action: player.togglePlayPause) {
                            Image(systemName: player.state == .playing ? "pause.circle.fill" : "play.circle.fill")
                                .font(.system(size: 62))
                        }
                        .disabled(player.currentTrack == nil)

                        Button(action: player.playNext) {
                            Image(systemName: "forward.fill").font(.title2)
                        }

                        Button {
                            player.repeatMode = nextRepeatMode(player.repeatMode)
                        } label: {
                            Image(systemName: repeatIcon(player.repeatMode))
                                .foregroundStyle(player.repeatMode == .off ? .primary : Color.accentColor)
                        }
                    }
                    .font(.title3)
                    .foregroundStyle(.primary)

                    HStack(spacing: 18) {
                        Button { player.skipBackward() } label: {
                            Image(systemName: "gobackward.15")
                        }

                        SpeedMenu(rate: $player.playbackRate)

                        AirPlayButton()
                            .frame(width: 32, height: 32)

                        Button {
                            showingEqualizer = true
                        } label: {
                            Image(systemName: "slider.horizontal.3")
                        }

                        Button { player.skipForward() } label: {
                            Image(systemName: "goforward.15")
                        }
                    }
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)

                    Spacer(minLength: 8)
                }
                .padding(.horizontal, 20)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle("Сейчас играет")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { dismiss() } label: { Image(systemName: "chevron.down") }
                }
            }
            .sheet(isPresented: $showingEqualizer) {
                EqualizerView(equalizer: equalizer)
            }
            .sheet(isPresented: $showingEditTrack) {
                if let track = player.currentTrack {
                    EditTrackSheet(track: track, player: player, library: library)
                }
            }
        }
    }

    private func repeatIcon(_ mode: AudioEngine.RepeatMode) -> String {
        switch mode {
        case .off: return "repeat"
        case .all: return "repeat"
        case .single: return "repeat.1"
        }
    }

    private func nextRepeatMode(_ mode: AudioEngine.RepeatMode) -> AudioEngine.RepeatMode {
        switch mode {
        case .off: return .all
        case .all: return .single
        case .single: return .off
        }
    }
}

/// Speed picker (0.5x – 2x), a staple of real audio/podcast players.
private struct SpeedMenu: View {
    @Binding var rate: Float
    private let steps: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0]

    var body: some View {
        Menu {
            ForEach(steps, id: \.self) { step in
                Button {
                    rate = step
                } label: {
                    if rate == step {
                        Label(speedLabel(step), systemImage: "checkmark")
                    } else {
                        Text(speedLabel(step))
                    }
                }
            }
        } label: {
            Text(speedLabel(rate))
                .font(.caption.monospacedDigit().weight(.semibold))
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Capsule().fill(Color.secondary.opacity(0.15)))
        }
    }

    private func speedLabel(_ v: Float) -> String {
        v.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(v))x" : String(format: "%.2gx", v)
    }
}

/// Wraps AVRoutePickerView (AirPlay / Bluetooth output picker) for SwiftUI.
private struct AirPlayButton: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.prioritizesVideoDevices = false
        return view
    }
    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}
