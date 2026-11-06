import Foundation
import Testing
@testable import Siphon

struct URLNormalizerTests {
    @Test func ignoresTrackingWwwFragmentAndScheme() {
        let a = URLNormalizer.normalize("http://www.Example.com/watch?v=abc&utm_source=x&si=123#t=30")
        let b = URLNormalizer.normalize("https://example.com/watch?v=abc")
        #expect(a == b)
    }

    @Test func keepsMeaningfulQueryAndPath() {
        #expect(URLNormalizer.normalize("https://example.com/watch?v=abc")
            != URLNormalizer.normalize("https://example.com/watch?v=xyz"))
        #expect(URLNormalizer.normalize("https://example.com/a/") == URLNormalizer.normalize("https://example.com/a"))
        #expect(URLNormalizer.normalize("https://x.com/v?b=2&a=1") == URLNormalizer.normalize("https://x.com/v?a=1&b=2"))
    }
}

@MainActor
struct DownloadHistoryTests {
    private func scratch() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("siphon-history-\(UUID().uuidString)", isDirectory: true)
    }

    @Test func duplicatesNeedTheFileToStillExist() throws {
        let folder = scratch()
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent("clip.mp4")
        try Data("x".utf8).write(to: file)

        let history = DownloadHistory(fileURL: folder.appendingPathComponent("history.json"))
        history.record(HistoryEntry(url: "https://www.example.com/v/1?utm_source=a", filePath: file.path,
                                    videoKey: "Example:1", downloadedAt: Date()))
        #expect(history.duplicate(ofURL: "https://example.com/v/1") != nil)
        #expect(history.duplicate(ofVideoKey: "Example:1") != nil)
        #expect(history.duplicate(ofURL: "https://example.com/v/2") == nil)

        try FileManager.default.removeItem(at: file)
        #expect(history.duplicate(ofURL: "https://example.com/v/1") == nil)
        #expect(history.duplicate(ofVideoKey: "Example:1") == nil)
    }

    @Test func persistsAndClears() {
        let folder = scratch()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("history.json")
        let history = DownloadHistory(fileURL: url)
        history.record(HistoryEntry(url: "https://a.com/1", title: "One", downloadedAt: Date()))
        #expect(DownloadHistory(fileURL: url).entries.map(\.title) == ["One"])
        history.clear()
        #expect(DownloadHistory(fileURL: url).entries.isEmpty)
    }

    @Test func queueHoldsALinkDownloadedBefore() throws {
        let folder = scratch()
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent("clip.mp4")
        try Data("x".utf8).write(to: file)
        let history = DownloadHistory(fileURL: folder.appendingPathComponent("history.json"))
        history.record(HistoryEntry(url: "https://example.com/v/1", title: "Clip", filePath: file.path, downloadedAt: Date()))

        let queue = DownloadQueue(
            store: QueueStore(fileURL: folder.appendingPathComponent("queue.json")),
            siteStore: SiteStore(folder: folder.appendingPathComponent("sites", isDirectory: true)),
            bundledSites: nil,
            history: history)
        #expect(queue.add(text: "https://www.example.com/v/1#top", destination: folder.path) == 1)
        let item = try #require(queue.items.first)
        #expect(item.status == .paused)
        #expect(item.heldAsDuplicate == true)
        #expect(item.title == "Clip")
        #expect(queue.lastAddHeldDuplicates == 1)
        #expect(!queue.hasPaused)
    }
}
