import Foundation

/// Saves the queue as JSON in Application Support, written atomically.
struct QueueStore {
    var fileURL: URL

    static var defaultFileURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("Siphon", isDirectory: true).appendingPathComponent("queue.json")
    }

    func load() -> [QueueItem] {
        guard let data = try? Data(contentsOf: fileURL),
              let items = try? JSONDecoder().decode([QueueItem].self, from: data) else { return [] }
        // A download that was running when the app quit resumes from its partial file
        return items.map { item in
            var item = item
            if item.status == .downloading { item.status = .pending }
            return item
        }
    }

    func save(_ items: [QueueItem]) {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(items).write(to: fileURL, options: .atomic)
        } catch {
            NSLog("Siphon: could not save the queue: \(error.localizedDescription)")
        }
    }
}
