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
        let pluginFile = bundled.appendingPathComponent("plugins/siphon/yt_dlp_plugins/extractor/demo.py")
        try FileManager.default.createDirectory(at: pluginFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("# demo".utf8).write(to: pluginFile)
        try Data(#"{"sites":[{"id":"a","match":["a.com"],"lastTested":"2026-11-01"}]}"#.utf8)
            .write(to: bundled.appendingPathComponent("sites.json"))

        let store = SiteStore(folder: root.appendingPathComponent("user"))
        let registry = store.prepare(bundled: bundled)
        #expect(registry.sites.map(\.id) == ["a"])
        #expect(FileManager.default.fileExists(atPath: store.pluginsURL.appendingPathComponent("siphon/yt_dlp_plugins/extractor/demo.py").path))

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
        #expect(plain.count == 6)
        #expect(plain[2].arguments.contains("Referer:https://example.com/"))
        #expect(plain[4].recipe == .followEmbed)
        #expect(plain[5].recipe == .smartScan)
        #expect(plain.prefix(4).allSatisfy { $0.recipe == nil })

        let saved = SiteConfig(id: "e", name: "e", match: ["example.com"], method: "options", status: "working",
                               ytDlpArgs: ["--impersonate", "chrome"], source: "learned")
        let again = SiteLearner.attempts(for: "https://example.com/v/1", existing: saved)
        #expect(again.first?.arguments == ["--impersonate", "chrome"])
        #expect(again.count == 6)

        let embedSite = SiteConfig(id: "e", name: "e", match: ["example.com"], method: "recipe", status: "working",
                                   source: "learned", recipe: .followEmbed)
        let embedFirst = SiteLearner.attempts(for: "https://example.com/v/1", existing: embedSite)
        #expect(embedFirst.first?.followEmbed == true)
        #expect(embedFirst.count == 6)

        let recipeSite = SiteConfig(id: "r", name: "r", match: ["example.com"], method: "recipe", status: "broken",
                                    recipe: Recipe(embed: .init(match: "player\\.example"), media: .sources))
        let recipeFirst = SiteLearner.attempts(for: "https://example.com/v/1", existing: recipeSite)
        #expect(recipeFirst.first?.recipe?.embed?.match == "player\\.example")
        #expect(recipeFirst.count == 7)
    }

    @Test func smartScanEntryRecordsRecipe() throws {
        let attempt = SiteLearner.Attempt(label: "reading video sources", arguments: [], recipe: .smartScan)
        let entry = try #require(SiteLearner.workingEntry(
            url: "https://hqporner.com/hdporn/1-x.html", attempt: attempt, extractor: "Generic",
            firstFailure: "Unsupported URL", testResult: "Downloaded", existing: nil,
            embedURL: URL(string: "https://mydaddy.cc/video/abc/")))
        #expect(entry.method == "recipe")
        #expect(entry.recipe == .smartScan)
        #expect(entry.notes?.contains("mydaddy.cc") == true)
    }

    @Test func embedEntryIsRecordedAsRecipe() throws {
        let attempt = SiteLearner.Attempt(label: "following the page's embedded player", arguments: [], recipe: .followEmbed)
        let entry = try #require(SiteLearner.workingEntry(
            url: "https://puncher.tube/video/1/x.html", attempt: attempt, extractor: "Generic",
            firstFailure: "Unsupported URL", testResult: "Downloaded 74.8 MB", existing: nil,
            embedURL: URL(string: "https://x-x-x.tube/embed/270856/")))
        #expect(entry.method == "recipe")
        #expect(entry.recipe == .followEmbed)
        #expect(entry.notes?.contains("x-x-x.tube") == true)
    }

    @Test func legacyEmbedEntriesAreRewrittenAsRecipes() throws {
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("siphon-legacy-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: scratch) }
        let store = SiteStore(folder: scratch.appendingPathComponent("user"))
        let bundled = scratch.appendingPathComponent("bundled")
        try FileManager.default.createDirectory(at: store.folder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: bundled, withIntermediateDirectories: true)
        try Data(#"{"sites":[]}"#.utf8).write(to: bundled.appendingPathComponent("sites.json"))
        try Data(#"""
        {"sites":[{"id":"p","name":"P","match":["puncher.tube"],"method":"embed","status":"working",
                   "source":"learned","followEmbed":true}]}
        """#.utf8).write(to: store.fileURL)

        let site = try #require(store.prepare(bundled: bundled).sites.first)
        #expect(site.method == "recipe")
        #expect(site.recipe == .followEmbed)
        let rewritten = try String(contentsOf: store.fileURL, encoding: .utf8)
        #expect(!rewritten.contains("followEmbed"))
        #expect(rewritten.contains(#""media" : "ytdlp""#))
    }

    @Test func sitesWindowSortsByNameAndSearches() {
        func site(_ name: String, _ domain: String, status: String = "working") -> SiteConfig {
            SiteConfig(id: domain, name: name, match: [domain], method: "builtin", status: status)
        }
        let sites = [site("txxx.com", "txxx.com"), site("aShemaleTube", "ashemaletube.com"),
                     site("iStock preview videos", "media.istockphoto.com"), site("eporner.com", "eporner.com", status: "broken")]
        #expect(SitesView.visible(sites, matching: "").map(\.name)
                == ["aShemaleTube", "eporner.com", "iStock preview videos", "txxx.com"])
        #expect(SitesView.visible(sites, matching: "istockphoto").map(\.name) == ["iStock preview videos"])
        #expect(SitesView.visible(sites, matching: "BROKEN").map(\.name) == ["eporner.com"])
        #expect(SitesView.visible(sites, matching: "builtin com").count == 4)
        #expect(SitesView.visible(sites, matching: "nothing").isEmpty)
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
        #expect(YtDlpOutputParser.parse(line: "SIPHON-EXTRACTOR Generic|clip-1|NA")
            == .extractor(name: "Generic", videoID: "clip-1", inPlaylist: false))
        #expect(YtDlpOutputParser.parse(line: "SIPHON-EXTRACTOR Youtube|abc|3")
            == .extractor(name: "Youtube", videoID: "abc", inPlaylist: true))
    }
}
