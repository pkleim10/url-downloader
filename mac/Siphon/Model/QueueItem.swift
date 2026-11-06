import Foundation

enum DownloadStatus: String, Codable {
    case pending, downloading, paused, failed, completed

    var label: String {
        switch self {
        case .pending: "Pending"
        case .downloading: "Downloading"
        case .paused: "Paused"
        case .failed: "Failed"
        case .completed: "Done"
        }
    }
}

struct QueueItem: Identifiable, Codable, Equatable {
    let id: UUID
    var url: String
    var prefix: String
    var destination: String
    var status: DownloadStatus
    var addedAt: Date
    var title: String?
    var siteName: String?
    var failReason: String?
    var filePath: String?
    /// Paused because it was downloaded before; resuming downloads it anyway.
    var heldAsDuplicate: Bool?
    var allowDuplicate: Bool?

    // Live progress; not saved
    var fraction: Double?
    var downloadedBytes: Int64?
    var totalBytes: Int64?
    var speed: Double?
    var eta: Int?
    /// What Siphon is doing about the site, e.g. "Trying fix 2 of 3"; not saved.
    var note: String?

    enum CodingKeys: String, CodingKey {
        case id, url, prefix, destination, status, addedAt, title, siteName, failReason, filePath
        case heldAsDuplicate, allowDuplicate
    }

    init(url: String, prefix: String = "", destination: String, status: DownloadStatus = .pending) {
        id = UUID()
        self.url = url
        self.prefix = prefix
        self.destination = destination
        self.status = status
        addedAt = Date()
    }

    var displayTitle: String { title ?? url }

    mutating func clearProgress() {
        fraction = nil
        downloadedBytes = nil
        totalBytes = nil
        speed = nil
        eta = nil
    }
}

/// Picks which pending items to start: oldest first, up to the free slots.
enum QueueScheduler {
    static func itemsToStart(in items: [QueueItem], limit: Int) -> [UUID] {
        let running = items.filter { $0.status == .downloading }.count
        let free = max(0, limit - running)
        return Array(items.filter { $0.status == .pending }.prefix(free).map(\.id))
    }
}

/// Splits pasted or dropped text into http(s) links.
enum LinkExtractor {
    static func links(in text: String) -> [String] {
        text.split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
            .filter { token in
                guard let url = URL(string: token), let scheme = url.scheme?.lowercased(),
                      scheme == "http" || scheme == "https", url.host != nil else { return false }
                return true
            }
    }
}
