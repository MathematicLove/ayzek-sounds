import Foundation
import AVFoundation
import UIKit

/// Owns the on-disk library: imported audio files, their metadata cache and recently-played list.
final class LibraryStore: ObservableObject {
    @Published var tracks: [Track] = [] { didSet { saveTracks() } }
    @Published var recentIDs: [UUID] = [] { didSet { saveRecents() } }
    @Published var isImporting: Bool = false

    private let tracksKey  = "tracks_v3"
    private let recentsKey = "recents_v1"
    private let recentsLimit = 30

    init() {
        loadTracks()
        loadRecents()
    }

    // MARK: Persistence

    private func loadTracks() {
        guard let data = UserDefaults.standard.data(forKey: tracksKey) else { return }
        if let decoded = try? JSONDecoder().decode([Track].self, from: data) {
            tracks = decoded
        }
    }
    private func saveTracks() {
        if let data = try? JSONEncoder().encode(tracks) {
            UserDefaults.standard.set(data, forKey: tracksKey)
        }
    }

    private func loadRecents() {
        guard let data = UserDefaults.standard.data(forKey: recentsKey) else { return }
        if let decoded = try? JSONDecoder().decode([UUID].self, from: data) {
            recentIDs = decoded
        }
    }
    private func saveRecents() {
        if let data = try? JSONEncoder().encode(recentIDs) {
            UserDefaults.standard.set(data, forKey: recentsKey)
        }
    }

    // MARK: Recents

    func addToRecents(_ track: Track) {
        recentIDs.removeAll { $0 == track.id }
        recentIDs.insert(track.id, at: 0)
        if recentIDs.count > recentsLimit {
            recentIDs.removeLast(recentIDs.count - recentsLimit)
        }
    }
    var recentTracks: [Track] {
        recentIDs.compactMap { id in tracks.first(where: { $0.id == id }) }
    }
    func clearRecents() {
        recentIDs.removeAll()
    }

    // MARK: Paths

    private func libraryDir() -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dir = docs.appendingPathComponent("Imported", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func artworkDir() -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dir = docs.appendingPathComponent("Artwork", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func absoluteURL(for track: Track) -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent(track.localRelativePath)
    }

    func artworkURL(for track: Track) -> URL? {
        guard let rel = track.artworkRelativePath else { return nil }
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent(rel)
    }

    // MARK: Import

    func add(urls: [URL]) {
        isImporting = true
        let destDir = libraryDir()
        let artDir = artworkDir()

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            var imported: [Track] = []

            for srcURL in urls {
                let accessed = srcURL.startAccessingSecurityScopedResource()
                defer { if accessed { srcURL.stopAccessingSecurityScopedResource() } }

                let base = srcURL.deletingPathExtension().lastPathComponent
                let ext  = srcURL.pathExtension.isEmpty ? "mp3" : srcURL.pathExtension

                var dest = destDir.appendingPathComponent("\(base).\(ext)")
                var n = 1
                while FileManager.default.fileExists(atPath: dest.path) {
                    dest = destDir.appendingPathComponent("\(base) (\(n)).\(ext)")
                    n += 1
                }

                do {
                    _ = try? FileManager.default.startDownloadingUbiquitousItem(at: srcURL)
                    try FileManager.default.copyItem(at: srcURL, to: dest)

                    let asset = AVURLAsset(url: dest)
                    let secs = CMTimeGetSeconds(asset.duration)
                    let relPath = "Imported/\(dest.lastPathComponent)"

                    var title = dest.deletingPathExtension().lastPathComponent
                    var artist: String?
                    var artworkRelPath: String?

                    let metadata = asset.commonMetadata
                    if let titleItem = AVMetadataItem.metadataItems(from: metadata, filteredByIdentifier: .commonIdentifierTitle).first,
                       let value = titleItem.stringValue, !value.isEmpty {
                        title = value
                    }
                    if let artistItem = AVMetadataItem.metadataItems(from: metadata, filteredByIdentifier: .commonIdentifierArtist).first,
                       let value = artistItem.stringValue, !value.isEmpty {
                        artist = value
                    }
                    if let artworkItem = AVMetadataItem.metadataItems(from: metadata, filteredByIdentifier: .commonIdentifierArtwork).first,
                       let data = artworkItem.dataValue, UIImage(data: data) != nil {
                        let fileName = "\(UUID().uuidString).jpg"
                        let fileURL = artDir.appendingPathComponent(fileName)
                        try? data.write(to: fileURL)
                        artworkRelPath = "Artwork/\(fileName)"
                    }

                    let t = Track(title: title, artist: artist, localRelativePath: relPath,
                                  duration: secs, artworkRelativePath: artworkRelPath, dateAdded: Date())
                    imported.append(t)
                } catch {
                    print("Copy error: \(error)")
                }
            }

            DispatchQueue.main.async {
                for t in imported where !self.tracks.contains(where: { $0.localRelativePath == t.localRelativePath }) {
                    self.tracks.append(t)
                }
                self.isImporting = false
            }
        }
    }

    func remove(at offsets: IndexSet) {
        let items = offsets.map { tracks[$0] }
        for t in items { delete(t) }
        tracks.remove(atOffsets: offsets)
    }

    func remove(track: Track) {
        if let idx = tracks.firstIndex(where: { $0.id == track.id }) {
            delete(track)
            tracks.remove(at: idx)
        }
    }

    private func delete(_ t: Track) {
        try? FileManager.default.removeItem(at: absoluteURL(for: t))
        if let art = artworkURL(for: t) { try? FileManager.default.removeItem(at: art) }
        recentIDs.removeAll { $0 == t.id }
    }

    func rename(track: Track, to newTitle: String) {
        guard let idx = tracks.firstIndex(where: { $0.id == track.id }) else { return }
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        tracks[idx].title = trimmed
    }

    func update(_ track: Track) {
        guard let idx = tracks.firstIndex(where: { $0.id == track.id }) else { return }
        tracks[idx] = track
    }

    func track(after currentTrack: Track, in order: [Track]) -> Track? {
        guard let currentIndex = order.firstIndex(where: { $0.id == currentTrack.id }) else { return nil }
        let nextIndex = order.index(after: currentIndex)
        return nextIndex < order.count ? order[nextIndex] : order.first
    }

    func track(before currentTrack: Track, in order: [Track]) -> Track? {
        guard let currentIndex = order.firstIndex(where: { $0.id == currentTrack.id }) else { return nil }
        if currentIndex == order.startIndex { return order.last }
        return order[order.index(before: currentIndex)]
    }
}
