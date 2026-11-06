import Foundation
import Testing
@testable import Siphon

/// Runs the real yt-dlp over the network. `scripts/build_and_install.sh` skips this suite;
/// run it with `--integration`. The download is deleted afterwards unless /tmp/siphon-keep exists.
@MainActor
struct IntegrationTests {
    static let sampleURL = "https://media.istockphoto.com/id/497375361/video/super-mother-and-daughter-running-to-the-sun.mp4?s=mp4-640x640-is&k=20&c=7RwPyzlurnRxyriCTKqzFMqgT6XrqIHNScD9C9esT38="

    @Test(.timeLimit(.minutes(2)))
    func queueDownloadsTheISTockSample() async throws {
        let scratch = URL(fileURLWithPath: "/tmp/siphon-integration-\(UUID().uuidString)", isDirectory: true)
        let keep = FileManager.default.fileExists(atPath: "/tmp/siphon-keep")
        defer { if !keep { try? FileManager.default.removeItem(at: scratch) } }

        let sitesFolder = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("sites", isDirectory: true)
        let queue = DownloadQueue(
            store: QueueStore(fileURL: scratch.appendingPathComponent("queue.json")),
            siteStore: SiteStore(folder: scratch.appendingPathComponent("sites", isDirectory: true)),
            bundledSites: sitesFolder
        )
        #expect(queue.add(text: Self.sampleURL, prefix: "test", destination: scratch.path) == 1)

        var item = try #require(queue.items.first)
        #expect(item.siteName == "iStock preview videos")
        while item.status == .pending || item.status == .downloading {
            try await Task.sleep(for: .milliseconds(200))
            item = try #require(queue.items.first)
        }

        #expect(item.status == .completed, "failed: \(item.failReason ?? "-")")
        let path = try #require(item.filePath)
        #expect(path.hasPrefix(scratch.path + "/test-"))
        let size = try FileManager.default.attributesOfItem(atPath: path)[.size] as? Int64
        #expect(size == 5_587_508)
        if keep { print("SIPHON_FILE=\(path)") }
    }

    /// With no bundled entry the site is new: Siphon downloads it, checks the file, and records it.
    @Test(.timeLimit(.minutes(2)))
    func unknownSiteIsLearnedAndRecorded() async throws {
        let scratch = URL(fileURLWithPath: "/tmp/siphon-integration-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        let emptyBundle = scratch.appendingPathComponent("bundled", isDirectory: true)
        try FileManager.default.createDirectory(at: emptyBundle, withIntermediateDirectories: true)
        try Data(#"{"sites":[]}"#.utf8).write(to: emptyBundle.appendingPathComponent("sites.json"))

        let siteStore = SiteStore(folder: scratch.appendingPathComponent("sites", isDirectory: true))
        let queue = DownloadQueue(
            store: QueueStore(fileURL: scratch.appendingPathComponent("queue.json")),
            siteStore: siteStore,
            bundledSites: emptyBundle
        )
        #expect(queue.add(text: Self.sampleURL, destination: scratch.path) == 1)

        var entry: SiteConfig?
        for _ in 0..<500 where entry == nil {
            try await Task.sleep(for: .milliseconds(200))
            entry = siteStore.load().first
        }
        let learned = try #require(entry)
        let item = try #require(queue.items.first)
        #expect(item.status == .completed, "failed: \(item.failReason ?? "-")")
        #expect(learned.match == ["media.istockphoto.com"])
        #expect(learned.status == "working")
        #expect(learned.method == "builtin")
        #expect(learned.isLearned)
        #expect(learned.testResult?.contains("H.264 768x432") == true, "\(learned.testResult ?? "-")")
        #expect(queue.sites.site(for: Self.sampleURL)?.id == learned.id)
    }
}
