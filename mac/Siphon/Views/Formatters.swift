import Foundation

enum Formatters {
    static func bytes(_ count: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: count, countStyle: .file)
    }

    static func speed(_ bytesPerSecond: Double) -> String {
        bytes(Int64(bytesPerSecond)) + "/s"
    }

    static func eta(_ seconds: Int) -> String {
        let h = seconds / 3600, m = (seconds % 3600) / 60, s = seconds % 60
        return h > 0 ? String(format: "%d:%02d:%02d left", h, m, s) : String(format: "%d:%02d left", m, s)
    }

    /// "45.2% · 12.3 MB of 92 MB · 4.1 MB/s · 0:21 left", skipping unknown parts.
    static func progressDetail(for item: QueueItem) -> String {
        var parts: [String] = []
        if let fraction = item.fraction {
            parts.append(String(format: "%.1f%%", fraction * 100))
        }
        if let done = item.downloadedBytes {
            parts.append(item.totalBytes.map { "\(bytes(done)) of \(bytes($0))" } ?? bytes(done))
        }
        if let speed = item.speed { parts.append(self.speed(speed)) }
        if let eta = item.eta, item.status == .downloading { parts.append(self.eta(eta)) }
        return parts.joined(separator: " · ")
    }
}
