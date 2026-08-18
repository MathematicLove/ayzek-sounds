import SwiftUI

/// A real 10-band graphic equalizer: presets, per-band vertical sliders and a preamp control.
struct EqualizerView: View {
    @ObservedObject var equalizer: EqualizerStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                Toggle(isOn: $equalizer.state.isEnabled) {
                    Label("Эквалайзер", systemImage: "slider.horizontal.3")
                        .font(.headline)
                }
                .padding(.horizontal)
                .padding(.top, 8)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(EQPreset.all) { preset in
                            PresetChip(
                                title: preset.name,
                                isSelected: equalizer.state.activePresetName == preset.name,
                                action: { equalizer.applyPreset(preset) }
                            )
                        }
                    }
                    .padding(.horizontal)
                }
                .opacity(equalizer.state.isEnabled ? 1 : 0.4)
                .disabled(!equalizer.state.isEnabled)

                HStack(alignment: .bottom, spacing: 10) {
                    ForEach(Array(eqFrequencies.enumerated()), id: \.offset) { index, freq in
                        BandSlider(
                            label: EQBand(id: index, frequency: freq, gain: 0).label,
                            gain: Binding(
                                get: { equalizer.state.bandGains.indices.contains(index) ? equalizer.state.bandGains[index] : 0 },
                                set: { equalizer.setBandGain(index: index, gain: $0) }
                            )
                        )
                    }
                }
                .padding(.horizontal, 12)
                .opacity(equalizer.state.isEnabled ? 1 : 0.4)
                .disabled(!equalizer.state.isEnabled)

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Предусиление")
                            .font(.subheadline)
                        Spacer()
                        Text(dBString(equalizer.state.preampDB))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $equalizer.state.preampDB, in: -24...24, step: 0.5)
                }
                .padding(.horizontal)
                .opacity(equalizer.state.isEnabled ? 1 : 0.4)
                .disabled(!equalizer.state.isEnabled)

                Spacer()

                Button(role: .destructive) {
                    equalizer.reset()
                } label: {
                    Label("Сбросить", systemImage: "arrow.counterclockwise")
                }
                .padding(.bottom, 12)
            }
            .navigationTitle("Эквалайзер")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Готово") { dismiss() }
                }
            }
        }
    }
}

private struct PresetChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(isSelected ? .semibold : .regular))
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(
                    Capsule().fill(isSelected ? Color.accentColor : Color.secondary.opacity(0.15))
                )
                .foregroundStyle(isSelected ? .white : .primary)
        }
        .buttonStyle(.plain)
    }
}

/// One vertical slider representing a single EQ band, styled like a mixing-desk fader.
private struct BandSlider: View {
    let label: String
    @Binding var gain: Float
    private let range: ClosedRange<Float> = -12...12

    var body: some View {
        VStack(spacing: 6) {
            Text(String(format: "%+.0f", gain))
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)

            GeometryReader { geo in
                let height = geo.size.height
                let ratio = CGFloat((gain - range.lowerBound) / (range.upperBound - range.lowerBound))
                ZStack(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.secondary.opacity(0.15))
                        .frame(width: 6)
                        .frame(maxWidth: .infinity)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.accentColor)
                        .frame(width: 6, height: max(4, ratio * height))
                        .frame(maxWidth: .infinity, alignment: .bottom)
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 20, height: 20)
                        .shadow(radius: 1)
                        .offset(y: -max(4, ratio * height) + 10)
                }
                .frame(maxWidth: .infinity, alignment: .bottom)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let clampedY = min(max(0, value.location.y), height)
                            let newRatio = 1 - Double(clampedY / height)
                            let newGain = range.lowerBound + Float(newRatio) * (range.upperBound - range.lowerBound)
                            gain = min(max(newGain, range.lowerBound), range.upperBound)
                        }
                )
            }
            .frame(height: 150)

            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
