import Foundation
import Testing
@testable import Siphon

struct SiteStoreTests {
    private func site(_ id: String, _ domain: String, tested: String?, learned: Bool = false, status: String = "working") -> SiteConfig {
        SiteConfig(id: id, name: id, match: [domain], method: "builtin", status: status,
                   lastTested: tested, source: learned ? "learned" : nil)
    }

    @Test func newBundledEntriesAreAddedAndLearnedOnesKept() {
        let merged = SiteStore.merge(
            user: [site("learned-a", "a.com", tested: "2026-11-06", learned: true)],
            bundled: [site("b", "b.com", tested: "2026-11-01")]
        )
        #expect(merged.map(\.id) == ["learned-a", "b"])
    }

    @Test func newerBundledEntryReplacesOlderCopyAndOverlappingLearnedEntry() {
        let merged = SiteStore.merge(
            user: [site("x", "x.com", tested: "2026-10-01"), site("x-com", "www.x.com", tested: "2026-10-02", learned: true)],
            bundled: [site("x", "x.com", tested: "2026-11-01")]
        )
        #expect(merged.count == 1)
        #expect(merged.first?.lastTested == "2026-11-01")
        #expect(merged.first?.isLearned == false)
    }

    @Test func fixLearnedAfterTheShippedEntrySurvivesMerge() {
        let merged = SiteStore.merge(
            user: [site("x-com", "x.com", tested: "2026-11-06", learned: true)],
            bundled: [site("x", "x.com", tested: "2026-11-01", status: "broken")]
        )
        #expect(merged.map(\.id) == ["x-com"])
    }

    @Test func prepareSeedsFromBundleAndRoundTrips() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("siphon-sitestore-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let bundled = root.appendingPathComponent("bundled")
        let pluginFile = bundled.appendingPathComponent("plugins/yt_dlp_plugins/extractor/demo.py")
        try FileManager.default.createDirectory(at: pluginFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("# demo".utf8).write(to: pluginFile)
        try Data(#"{"sites":[{"id":"a","match":["a.com"],"lastTested":"2026-11-01"}]}"#.utf8)
            .write(to: bundled.appendingPathComponent("sites.json"))

        let store = SiteStore(folder: root.appendingPathComponent("user"))
        let registry = store.prepare(bundled: bundled)
        #expect(registry.sites.map(\.id) == ["a"])
        #expect(FileManager.default.fileExists(atPath: store.pluginsURL.appendingPathComponent("yt_dlp_plugins/extractor/demo.py").path))

        store.save(registry.sites + [site("learned", "l.com", tested: "2026-11-06", learned: true)])
        #expect(store.prepare(bundled: bundled).sites.map(\.id) == ["a", "learned"])
    }
}

struct SiteLearnerTests {
    @Test func learnsUnknownAndLearnedSitesOnly() {
        #expect(SiteLearner.shouldLearn(nil))
        let curated = SiteConfig(id: "c", name: "c", match: ["c.com"], method: "builtin", status: "broken")
        #expect(!SiteLearner.shouldLearn(curated))
        var learned = curated
        learned.source = "learned"
        #expect(SiteLearner.shouldLearn(learned))
        learned.status = "unsupported"
        #expect(!SiteLearner.shouldLearn(learned))
    }

    @Test func domainDropsWwwAndMobilePrefixes() {
        #expect(SiteLearner.domain(for: "https://www.Example.com/v/1") == "example.com")
        #expect(SiteLearner.domain(for: "https://m.example.com/v/1") == "example.com")
        #expect(SiteLearner.domain(for: "https://media.example.com/v") == "media.example.com")
    }

    @Test func attemptsStartPlainThenFixesWithoutDuplicates() {
        let plain = SiteLearner.attempts(for: "https://example.com/v/1", existing: nil)
        #expect(plain.first?.arguments == [])
        #expect(plain.count == 4)
        #expect(plain[2].arguments.contains("Referer:https://example.com/"))

        let saved = SiteConfig(id: "e", name: "e", match: ["example.com"], method: "options", status: "working",
                               ytDlpArgs: ["--impersonate", "chrome"], source: "learned")
        let again = SiteLearner.attempts(for: "https://example.com/v/1", existing: saved)
        #expect(again.first?.arguments == ["--impersonate", "chrome"])
        #expect(again.count == 4)
    }

    @Test func classifiesFailures() {
        #expect(SiteLearner.classify("Unable to download webpage: <urlopen error [Errno 8] nodename nor servname provided>") == .local)
        #expect(SiteLearner.classify("This video is DRM protected") == .drm)
        #expect(SiteLearner.classify("[youtube] abc: Private video. Sign in if you've been granted access") == .itemSpecific)
        #expect(SiteLearner.classify("Unsupported URL: https://example.com/") == .site)
        #expect(SiteLearner.classify("HTTP Error 403: Forbidden") == .site)
    }

    @Test func workingEntryRecordsOptionsAndWhy() throws {
        let attempt = SiteLearner.Attempt(label: "browser impersonation", arguments: ["--impersonate", "chrome"])
        let entry = try #require(SiteLearner.workingEntry(
            url: "https://www.example.com/v/1", attempt: attempt, extractor: "Generic",
            firstFailure: "HTTP Error 403: Forbidden", testResult: "Downloaded 1 MB", existing: nil,
            date: Date(timeIntervalSince1970: 1_793_000_000)))
        #expect(entry.id == "example-com")
        #expect(entry.match == ["example.com"])
        #expect(entry.method == "options")
        #expect(entry.status == "working")
        #expect(entry.ytDlpArgs == ["--impersonate", "chrome"])
        #expect(entry.isLearned)
        #expect(entry.notes?.contains("HTTP Error 403") == true)
        #expect(entry.exampleUrl == "https://www.example.com/v/1")
    }

    @Test func drmFailureIsUnsupported() throws {
        let entry = try #require(SiteLearner.failedEntry(
            url: "https://example.com/v", kind: .drm, tried: [], firstFailure: nil,
            lastFailure: "DRM protected", existing: nil))
        #expect(entry.status == "unsupported")
        #expect(entry.method == "unsupported")
    }
}

struct LogTests {
    @Test @MainActor func shellQuotingOnlyQuotesWhenNeeded() {
        #expect(DownloadQueue.shellQuoted("--newline") == "--newline")
        #expect(DownloadQueue.shellQuoted("/tmp/Siphon Test/%(title)s.%(ext)s") == "'/tmp/Siphon Test/%(title)s.%(ext)s'")
        #expect(DownloadQueue.shellQuoted("it's") == "'it'\\''s'")
        #expect(DownloadQueue.shellQuoted("https://x.com/v?a=1&b=2") == "'https://x.com/v?a=1&b=2'")
    }
}

struct MediaProbeTests {
    @Test func summarizesStreams() {
        let json = Data("""
        {"streams":[{"codec_type":"video","codec_name":"h264","width":768,"height":432},
                    {"codec_type":"audio","codec_name":"aac"}],
         "format":{"duration":"29.833"}}
        """.utf8)
        let result = MediaProbe.summarize(json: json, size: 5_587_508)
        #expect(result.playable)
        #expect(result.summary.contains("H.264 768x432 video, AAC audio, 29.8 s"))
    }

    @Test func noStreamsIsNotPlayable() {
        #expect(!MediaProbe.summarize(json: Data(#"{"streams":[]}"#.utf8), size: 10).playable)
        #expect(!MediaProbe.summarize(json: nil, size: 10).playable)
    }

    @Test func parsesExtractorLine() {
        #expect(YtDlpOutputParser.parse(line: "SIPHON-EXTRACTOR Generic") == .extractor("Generic"))
    }
}
