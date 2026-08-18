import Foundation

/// A single audio track imported into the local library.
struct Track: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var title: String
    var artist: String?
    var localRelativePath: String
    var duration: Double
    /// Artwork extracted from the file itself (or set by the user) and cached locally.
    var artworkRelativePath: String?
    /// Optional remote artwork override, kept for backwards compatibility with manual URLs.
    var artworkURLString: String?
    var dateAdded: Date = Date()

    var displayArtist: String { artist?.isEmpty == false ? artist! : "Неизвестный исполнитель" }
}

enum LibrarySortOrder: String, CaseIterable, Identifiable {
    case dateAddedDesc = "Недавно добавленные"
    case titleAsc = "По названию"
    case artistAsc = "По исполнителю"
    case durationAsc = "По длительности"

    var id: String { rawValue }

    func sort(_ tracks: [Track]) -> [Track] {
        switch self {
        case .dateAddedDesc: return tracks.sorted { $0.dateAdded > $1.dateAdded }
        case .titleAsc: return tracks.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .artistAsc: return tracks.sorted { $0.displayArtist.localizedCaseInsensitiveCompare($1.displayArtist) == .orderedAscending }
        case .durationAsc: return tracks.sorted { $0.duration < $1.duration }
        }
    }
}
