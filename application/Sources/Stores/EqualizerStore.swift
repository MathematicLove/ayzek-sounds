import Foundation
import Combine

/// Persists the equalizer configuration and exposes it to the audio engine and the UI.
final class EqualizerStore: ObservableObject {
    @Published var state: EqualizerState = .default {
        didSet { save() }
    }

    private let key = "equalizer_state_v1"

    init() {
        load()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode(EqualizerState.self, from: data) else { return }
        state = decoded
    }

    private func save() {
        if let data = try? JSONEncoder().encode(state) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    func applyPreset(_ preset: EQPreset) {
        state.bandGains = preset.gains
        state.activePresetName = preset.name
    }

    func setBandGain(index: Int, gain: Float) {
        guard state.bandGains.indices.contains(index) else { return }
        state.bandGains[index] = gain
        state.activePresetName = "Свой"
    }

    func reset() {
        state = .default
    }
}
