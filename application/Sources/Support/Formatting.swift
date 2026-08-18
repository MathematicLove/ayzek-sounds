import Foundation
import UniformTypeIdentifiers

func timeString(_ seconds: Double) -> String {
    guard seconds.isFinite else { return "--:--" }
    let total = max(0, Int(seconds.rounded()))
    let h = total / 3600
    let m = (total % 3600) / 60
    let s = total % 60
    return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
}

func dBString(_ value: Float) -> String {
    let sign = value > 0 ? "+" : ""
    return "\(sign)\(String(format: "%.1f", value)) дБ"
}

extension UTType {
    static var mp3: UTType { UTType(filenameExtension: "mp3") ?? .audio }
}
