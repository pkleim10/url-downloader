import Foundation
import Testing
@testable import Siphon

struct SiteRegistryTests {
    private let json = """
    {"sites": [
      {"id": "istock-media", "name": "iStock preview videos", "match": ["media.istockphoto.com"],
       "method": "builtin", "status": "working", "ytDlpArgs": [], "plugin": null},
      {"id": "example", "name": "Example", "match": ["example.com"], "ytDlpArgs": ["--referer", "https://example.com/"]}
    ]}
    """

    private var registry: SiteRegistry {
        SiteRegistry(sites: SiteRegistry.decode(Data(json.utf8)), pluginDirectory: nil)
    }

    @Test func decodesEntriesWithMissingOptionalFields() {
        let sites = registry.sites
        #expect(sites.count == 2)
        #expect(sites[1].method == "builtin")
        #expect(sites[1].status == "untested")
        #expect(sites[1].ytDlpArgs == ["--referer", "https://example.com/"])
    }

    @Test func matchesDomainAndSubdomainsOnly() {
        #expect(registry.site(for: "https://media.istockphoto.com/id/1/video.mp4")?.id == "istock-media")
        #expect(registry.site(for: "https://cdn.example.com/a")?.id == "example")
        #expect(registry.site(for: "https://EXAMPLE.com/a")?.id == "example")
        #expect(registry.site(for: "https://notexample.com/a") == nil)
        #expect(registry.site(for: "https://www.istockphoto.com/video/1") == nil)
        #expect(registry.site(for: "not a url") == nil)
    }

    @Test func bundledSitesFileDecodes() throws {
        let file = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("sites/sites.json")
        let sites = SiteRegistry.decode(try Data(contentsOf: file))
        #expect(!sites.isEmpty)
    }
}

struct DownloadArgumentsTests {
    private let destination = URL(fileURLWithPath: "/tmp/Siphon Test", isDirectory: true)

    @Test func sanitizesPrefixLikeTheWebServer() {
        #expect(DownloadArguments.sanitizePrefix("My Show: S01/E02") == "My Show_ S01_E02")
        #expect(DownloadArguments.sanitizePrefix("ok_name-1") == "ok_name-1")
        #expect(DownloadArguments.sanitizePrefix("café") == "caf_")
    }

    @Test func outputTemplateWithAndWithoutPrefix() {
        #expect(DownloadArguments.outputTemplate(destination: destination, prefix: "")
            == "/tmp/Siphon Test/%(title)s.%(ext)s")
        #expect(DownloadArguments.outputTemplate(destination: destination, prefix: " Clip ")
            == "/tmp/Siphon Test/Clip-%(title)s.%(ext)s")
    }

    @Test func orderPutsPluginsAndSiteOptionsFirstAndUrlLast() throws {
        let site = try #require(SiteRegistry.decode(Data("""
        {"sites": [{"id": "x", "match": ["x.com"], "ytDlpArgs": ["--referer", "https://x.com/"]}]}
        """.utf8)).first)
        let args = DownloadArguments.build(
            url: "https://x.com/v/1",
            prefix: "",
            destination: destination,
            siteArguments: site.ytDlpArgs,
            pluginDirectory: URL(fileURLWithPath: "/tmp/plugins"),
            quality: .p1080
        )
        #expect(Array(args.prefix(4)) == ["--plugin-dirs", "/tmp/plugins", "--referer", "https://x.com/"])
        #expect(Array(args.suffix(2)) == ["--", "https://x.com/v/1"])
        let f = try #require(args.firstIndex(of: "-f"))
        #expect(args[f + 1].contains("height<=1080"))
        #expect(args.contains("--no-update"))
    }

    @Test func configFileQualityAddsNoFormat() {
        let args = DownloadArguments.build(
            url: "https://y.com/1", prefix: "", destination: destination,
            siteArguments: [], pluginDirectory: nil, quality: .configFile
        )
        #expect(!args.contains("-f"))
        #expect(!args.contains("--plugin-dirs"))
    }
}

struct OutputParserTests {
    @Test func parsesProgressWithUnknownFields() {
        let event = YtDlpOutputParser.parse(line: "SIPHON-PROGRESS 1024|5587508|NA|2048.5|12|NA|NA")
        guard case .progress(let p) = event else {
            Issue.record("expected progress, got \(event)")
            return
        }
        #expect(p.downloadedBytes == 1024)
        #expect(p.totalBytes == 5_587_508)
        #expect(p.estimatedTotalBytes == nil)
        #expect(p.speed == 2048.5)
        #expect(p.eta == 12)
        #expect(abs((p.fraction ?? 0) - 1024.0 / 5_587_508.0) < 1e-9)
    }

    @Test func fractionFallsBackToEstimateThenFragments() {
        #expect(DownloadProgress(downloadedBytes: 50, estimatedTotalBytes: 200).fraction == 0.25)
        #expect(DownloadProgress(downloadedBytes: 50, fragmentIndex: 3, fragmentCount: 4).fraction == 0.75)
        #expect(DownloadProgress(downloadedBytes: 50).fraction == nil)
        #expect(DownloadProgress(downloadedBytes: 300, totalBytes: 200).fraction == 1)
    }

    @Test func parsesTitleFileAndOtherLines() {
        #expect(YtDlpOutputParser.parse(line: "SIPHON-TITLE A | B") == .title("A | B"))
        #expect(YtDlpOutputParser.parse(line: "SIPHON-FILE /tmp/a b.mp4") == .file("/tmp/a b.mp4"))
        #expect(YtDlpOutputParser.parse(line: "[generic] Extracting URL") == .output("[generic] Extracting URL"))
    }

    @Test func failureReasonUsesLastErrorLine() {
        let lines = [
            "WARNING: something",
            "ERROR: first",
            "[generic] more",
            "ERROR: [generic] Unable to download webpage: HTTP Error 404: Not Found",
        ]
        #expect(YtDlpOutputParser.failureReason(from: lines, exitCode: 1)
            == "[generic] Unable to download webpage: HTTP Error 404: Not Found")
        #expect(YtDlpOutputParser.failureReason(from: ["no errors here"], exitCode: 2)
            == "yt-dlp stopped with exit code 2")
    }
}

struct QueueTests {
    private func item(_ status: DownloadStatus) -> QueueItem {
        QueueItem(url: "https://example.com/\(UUID())", destination: "/tmp", status: status)
    }

    @Test func schedulerFillsFreeSlotsOldestFirst() {
        let items = [item(.downloading), item(.paused), item(.pending), item(.failed), item(.pending), item(.pending)]
        let started = QueueScheduler.itemsToStart(in: items, limit: 3)
        #expect(started == [items[2].id, items[4].id])
    }

    @Test func schedulerStartsNothingWhenFull() {
        let items = [item(.downloading), item(.downloading), item(.pending)]
        #expect(QueueScheduler.itemsToStart(in: items, limit: 2).isEmpty)
        #expect(QueueScheduler.itemsToStart(in: items, limit: 1).isEmpty)
    }

    @Test func linkExtractorFindsOnlyWebLinks() {
        let text = """
        https://a.com/1  http://b.org/x?y=1
        not-a-link ftp://c.com/file mailto:me@d.com
        https://e.net/path
        """
        #expect(LinkExtractor.links(in: text) == ["https://a.com/1", "http://b.org/x?y=1", "https://e.net/path"])
    }

    @Test func storeRoundTripResumesInterruptedDownloads() throws {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("siphon-tests-\(UUID().uuidString)")
            .appendingPathComponent("queue.json")
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let store = QueueStore(fileURL: file)

        var running = item(.downloading)
        running.fraction = 0.5
        running.title = "Clip"
        let paused = item(.paused)
        store.save([running, paused])

        let loaded = store.load()
        #expect(loaded.map(\.status) == [.pending, .paused])
        #expect(loaded[0].title == "Clip")
        #expect(loaded[0].fraction == nil)
        #expect(loaded.map(\.id) == [running.id, paused.id])
    }
}
