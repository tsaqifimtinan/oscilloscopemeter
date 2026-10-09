import SwiftUI

/// Bottom control row for the spectrogram; hidden in clean mode like the scope's.
struct SpectrogramControls: View {
    @Binding var settings: SpectrogramSettings

    var body: some View {
        HStack(spacing: 14) {
            Picker("FFT", selection: $settings.fftSize) {
                ForEach(SpectrogramConfig.fftSizes, id: \.self) { Text("\($0)").tag($0) }
            }
            .fixedSize()
            Picker("History", selection: $settings.history) {
                ForEach(SpectrogramSettings.histories, id: \.self) { Text("\($0) s").tag($0) }
            }
            .fixedSize()
            Picker("Channel", selection: $settings.channel) {
                ForEach(SpectrogramChannel.allCases, id: \.self) { Text($0.rawValue) }
            }
            .fixedSize()
            Picker("Range", selection: $settings.range) {
                ForEach(FrequencyRange.allCases, id: \.self) { Text($0.rawValue) }
            }
            .fixedSize()
            Slider(value: $settings.floor, in: SpectrogramSettings.floorRange) {
                Text(String(format: "Floor %.0f", settings.floor)).monospacedDigit()
            }
            Slider(value: $settings.ceiling, in: SpectrogramSettings.ceilingRange) {
                Text(String(format: "Ceil %.0f", settings.ceiling)).monospacedDigit()
            }
            Slider(value: $settings.tilt, in: SpectrogramSettings.tiltRange) {
                Text(String(format: "Tilt %.1f", settings.tilt)).monospacedDigit()
            }
            Picker("Colors", selection: $settings.colormap) {
                ForEach(Colormap.allCases, id: \.self) { Text($0.rawValue) }
            }
            .fixedSize()
            Toggle("Labels", isOn: $settings.labels)
        }
        .controlSize(.small)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }
}
