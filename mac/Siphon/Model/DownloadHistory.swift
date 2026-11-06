import Foundation
import Observation

struct HistoryEntry: Identifiable, Codable, Equatable {
    var id = UUID()
    var url: String
    var title: String?
    var filePath: String?
    var siteName: String?
    /// "Youtube:dQw4w9WgXcQ": yt-dlp's extractor and video id, so the same video is
    /// recognized behind a different link.
    var videoKey: String?
    var sizeBytes: Int64?
    var downloadedAt: Date

    var displayTitle: String { title ?? url }

    var fileExists: Bool {
        filePath.map { FileManager.default.fileExists(atPath: $0) } ?? false
    }
}

/// Links that differ only in tracking parameters, "www.", or a fragment count as the same link.
enum URLNormalizer {
    static let trackingParameters: Set<String> = [
        "fbclid", "gclid", "dclid", "msclkid", "igshid", "si", "feature", "ref", "ref_src", "mc_cid", "mc_eid",
    ]

    static func normalize(_ link: String) -> String {
        guard var components = URLComponents(string: link.trimmingCharacters(in: .whitespaces)) else { return link }
        components.scheme = components.scheme?.lowercased()
        if var host = components.host?.lowercased() {
            if host.hasPrefix("www.") { host.removeFirst(4) }
            if host.hasPrefix("m.") { host.removeFirst(2) }
            components.host = host
        }
        components.fragment = nil
        let kept = (components.queryItems ?? []).filter { item in
            let name = item.name.lowercased()
            return !name.hasPrefix("utm_") && !trackingParameters.contains(name)
        }
        components.queryItems = kept.isEmpty ? nil : kept.sorted { ($0.name, $0.value ?? "") < ($1.name, $1.value ?? "") }
        if components.path.count > 1, components.path.hasSuffix("/") { components.path.removeLast() }
        if components.scheme == "http" { components.scheme = "https" }
        return components.string ?? link
    }
}

/// Finished downloads, newest first, saved as JSON in Application Support.
@MainActor
@Observable
final class DownloadHistory {
    private(set) var entries: [HistoryEntry] = []
    @ObservationIgnored private let fileURL: URL

    nonisolated static var defaultFileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Siphon/history.json")
    }

    init(fileURL: URL = DownloadHistory.defaultFileURL) {
        self.fileURL = fileURL
        if let data = try? Data(contentsOf: fileURL) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            entries = (try? decoder.decode([HistoryEntry].self, from: data)) ?? []
        }
    }

    func record(_ entry: HistoryEntry) {
        entries.insert(entry, at: 0)
        save()
    }

    func remove(_ id: UUID) {
        entries.removeAll { $0.id == id }
        save()
    }

    func clear() {
        entries.removeAll()
        save()
    }

    /// An earlier download of the same link whose file is still on disk.
    func duplicate(ofURL link: String) -> HistoryEntry? {
        let key = URLNormalizer.normalize(link)
        return entries.first { URLNormalizer.normalize($0.url) == key && $0.fileExists }
    }

    /// An earlier download of the same video (same extractor and id) whose file is still on disk.
    func duplicate(ofVideoKey videoKey: String) -> HistoryEntry? {
        entries.first { $0.videoKey == videoKey && $0.fileExists }
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(entries).write(to: fileURL, options: .atomic)
        } catch {
            NSLog("Siphon: could not save history: \(error.localizedDescription)")
        }
    }
}
