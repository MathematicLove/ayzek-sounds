import Foundation

/// One band of the graphic equalizer.
struct EQBand: Codable, Identifiable, Equatable {
    var id: Int
    var frequency: Float
    var gain: Float // dB, -12...12

    var label: String {
        if frequency >= 1000 {
            let khz = frequency / 1000
            return khz.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(khz))к" : String(format: "%.1fк", khz)
        }
        return "\(Int(frequency))"
    }
}

/// The 10 ISO-standard graphic-EQ center frequencies used across the app.
let eqFrequencies: [Float] = [32, 64, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]

struct EQPreset: Identifiable, Equatable {
    var id: String { name }
    let name: String
    let gains: [Float] // must match eqFrequencies.count

    static let flat = EQPreset(name: "Плоский", gains: [Float](repeating: 0, count: 10))

    static let all: [EQPreset] = [
        flat,
        EQPreset(name: "Бас+", gains: [7, 6, 5, 3, 1, 0, 0, 0, 0, 0]),
        EQPreset(name: "Бас−", gains: [-6, -5, -4, -2, -1, 0, 0, 0, 0, 0]),
        EQPreset(name: "Вокал", gains: [-2, -2, -1, 1, 3, 3, 2, 1, 0, -1]),
        EQPreset(name: "Верх+", gains: [0, 0, 0, 0, 0, 1, 2, 4, 5, 6]),
        EQPreset(name: "Рок", gains: [5, 3, -1, -2, -1, 1, 3, 5, 5, 5]),
        EQPreset(name: "Поп", gains: [-1, 1, 3, 4, 3, 0, -1, -1, -1, -1]),
        EQPreset(name: "Джаз", gains: [4, 3, 1, 2, -1, -1, 0, 2, 3, 4]),
        EQPreset(name: "Классика", gains: [4, 3, 2, 1, -1, -1, 0, 2, 3, 4]),
        EQPreset(name: "Электроника", gains: [5, 4, 1, 0, -2, 2, 1, 1, 4, 5]),
        EQPreset(name: "Хип-хоп", gains: [6, 5, 2, 2, -1, -1, 1, 1, 2, 3]),
        EQPreset(name: "Акустика", gains: [3, 2, 1, 1, 1, 1, 2, 2, 1, 1]),
        EQPreset(name: "В наушниках", gains: [2, 1, 0, 0, 0, 0, 1, 2, 3, 3]),
    ]
}

/// Persisted equalizer state: per-band gains, preamp and on/off, plus a "custom" marker.
struct EqualizerState: Codable, Equatable {
    var isEnabled: Bool = true
    var preampDB: Float = 0
    var bandGains: [Float] = EQPreset.flat.gains
    var activePresetName: String = EQPreset.flat.name

    static let `default` = EqualizerState()
}
