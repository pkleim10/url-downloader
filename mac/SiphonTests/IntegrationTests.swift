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
            sites: .load(from: sitesFolder)
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
}
