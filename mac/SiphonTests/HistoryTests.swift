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

    @Test func finishedItemMovesBelowTheLastCompletedOne() {
        func item(_ name: String, _ status: DownloadStatus) -> QueueItem {
            QueueItem(url: "https://example.com/\(name)", destination: "/tmp", status: status)
        }
        let done1 = item("done1", .completed), done2 = item("done2", .completed)
        let running = item("running", .downloading), pending = item("pending", .pending)
        var finished = item("finished", .downloading)
        finished.status = .completed
        let names = { (items: [QueueItem]) in items.map { String($0.url.split(separator: "/").last!) } }

        let queue = [done1, running, done2, pending, finished]
        #expect(names(DownloadQueue.movingBelowCompleted(finished.id, in: queue))
                == ["done1", "running", "done2", "finished", "pending"])
        let tidy = [done1, done2, running, finished, pending]
        #expect(names(DownloadQueue.movingBelowCompleted(finished.id, in: tidy))
                == ["done1", "done2", "finished", "running", "pending"])
        let first = [running, pending, finished]
        #expect(names(DownloadQueue.movingBelowCompleted(finished.id, in: first)) == ["finished", "running", "pending"])
    }

    @Test func reorderingWithFailedAndPausedHiddenKeepsThemInPlace() {
        func item(_ name: String, _ status: DownloadStatus) -> QueueItem {
            QueueItem(url: "https://example.com/\(name)", destination: "/tmp", status: status)
        }
        let all = [item("a", .downloading), item("failed", .failed), item("b", .pending),
                   item("paused", .paused), item("c", .pending)]
        let visible = all.filter { !DownloadQueue.isInactive($0) }
        #expect(visible.map { String($0.url.split(separator: "/").last!) } == ["a", "b", "c"])

        func moved(_ source: Int, to destination: Int) -> [String] {
            let (from, to) = DownloadQueue.fullOffsets(IndexSet(integer: source), destination,
                                                       visible: visible.map(\.id), all: all.map(\.id))
            var list = all
            list.move(fromOffsets: from, toOffset: to)
            return list.map { String($0.url.split(separator: "/").last!) }
        }
        #expect(moved(2, to: 0) == ["c", "a", "failed", "b", "paused"])
        #expect(moved(0, to: 3) == ["failed", "b", "paused", "c", "a"])
        #expect(moved(0, to: 2) == ["failed", "b", "paused", "a", "c"])
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
