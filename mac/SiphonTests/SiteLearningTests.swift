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

    @Test func removedEntryStaysOutUntilANewerOneShips() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = SiteStore(folder: root)
        store.save([site("a", "a.com", tested: "2026-11-01"), site("b", "b.com", tested: "2026-11-01")])
        store.remove("a")
        #expect(store.load().map(\.id) == ["b"])
        #expect(store.loadRemoved() == ["a": "2026-11-01"])

        let same = SiteStore.merge(user: store.load(), bundled: [site("a", "a.com", tested: "2026-11-01")],
                                   removed: store.loadRemoved())
        #expect(same.map(\.id) == ["b"])
        let newer = SiteStore.merge(user: store.load(), bundled: [site("a", "a.com", tested: "2026-12-01")],
                                    removed: store.loadRemoved())
        #expect(newer.map(\.id) == ["b", "a"])
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
    @Test func everyStandardEntryIsRetestedButHandWrittenStepsAreKept() {
        #expect(SiteLearner.shouldLearn(nil))
        var shipped = SiteConfig(id: "c", name: "c", match: ["c.com"], method: "builtin", status: "broken")
        #expect(SiteLearner.shouldLearn(shipped))
        shipped.recipe = .playerAPI
        #expect(SiteLearner.shouldLearn(shipped))
        shipped.recipe = SiteLearner.scanPage
        #expect(SiteLearner.shouldLearn(shipped))
        shipped.recipe = Recipe(link: .init(url: "/service/index.json"), media: .pattern, pattern: "(x)")
        #expect(!SiteLearner.shouldLearn(shipped), "a hand-written recipe is reported, never replaced")
        shipped.source = "learned"
        #expect(SiteLearner.shouldLearn(shipped))
        shipped.status = "unsupported"
        #expect(!SiteLearner.shouldLearn(shipped))
    }

    @Test func domainDropsWwwAndMobilePrefixes() {
        #expect(SiteLearner.domain(for: "https://www.Example.com/v/1") == "example.com")
        #expect(SiteLearner.domain(for: "https://m.example.com/v/1") == "example.com")
        #expect(SiteLearner.domain(for: "https://media.example.com/v") == "media.example.com")
    }

    @Test func attemptsStartPlainThenFixesWithoutDuplicates() {
        let plain = SiteLearner.attempts(for: "https://example.com/v/1", existing: nil)
        #expect(plain.first?.recipe == nil)
        #expect(plain.count == 10)
        #expect(plain[1].recipe?.downloadArguments(page: URL(string: "https://example.com/v/1")!) == ["--impersonate", "chrome"])
        #expect(plain[2].recipe?.downloadArguments(page: URL(string: "https://example.com/v/1")!)
                == ["--impersonate", "chrome", "--add-headers", "Referer:https://example.com/"])
        #expect(plain[3].recipe?.downloadArguments(page: URL(string: "https://example.com/v/1")!)
                == ["--impersonate", "chrome", "--use-extractors", "generic"])
        #expect(plain[1...3].allSatisfy { $0.recipe?.isDownloadOnly == true })
        #expect(plain[4].recipe == .followEmbed)
        #expect(plain[5].recipe == .embedPage)
        #expect(plain[6].recipe == .smartScan)
        #expect(plain[7].recipe == .playerConfig)
        #expect(plain[8].recipe == .pageSources)
        #expect(plain[9].recipe == .playerAPI)

        let saved = SiteConfig(id: "e", name: "e", match: ["example.com"], method: "recipe", status: "working",
                               source: "learned", recipe: SiteLearner.impersonate)
        let again = SiteLearner.attempts(for: "https://example.com/v/1", existing: saved)
        #expect(again.first?.recipe == SiteLearner.impersonate)
        #expect(again.first?.label == "the saved recipe")
        #expect(again.count == 10)

        let embedSite = SiteConfig(id: "e", name: "e", match: ["example.com"], method: "recipe", status: "working",
                                   source: "learned", recipe: .followEmbed)
        let embedFirst = SiteLearner.attempts(for: "https://example.com/v/1", existing: embedSite)
        #expect(embedFirst.first?.recipe == .followEmbed)
        #expect(embedFirst.count == 10)

        let recipeSite = SiteConfig(id: "r", name: "r", match: ["example.com"], method: "recipe", status: "broken",
                                    recipe: Recipe(embed: .init(match: "player\\.example"), media: .sources))
        let recipeFirst = SiteLearner.attempts(for: "https://example.com/v/1", existing: recipeSite)
        #expect(recipeFirst.first?.recipe?.embed?.match == "player\\.example")
        #expect(recipeFirst.count == 11)
    }

    @Test func smartScanEntryRecordsRecipe() throws {
        let attempt = SiteLearner.Attempt(label: "reading video sources", recipe: .smartScan)
        let entry = try #require(SiteLearner.workingEntry(
            url: "https://hqporner.com/hdporn/1-x.html", attempt: attempt, extractor: "Generic",
            firstFailure: "Unsupported URL", testResult: "Downloaded", existing: nil,
            embedURL: URL(string: "https://mydaddy.cc/video/abc/")))
        #expect(entry.method == "recipe")
        #expect(entry.recipe == .smartScan)
        #expect(entry.notes?.contains("mydaddy.cc") == true)
    }

    @Test func embedEntryIsRecordedAsRecipe() throws {
        let attempt = SiteLearner.Attempt(label: "following the page's embedded player", recipe: .followEmbed)
        let entry = try #require(SiteLearner.workingEntry(
            url: "https://puncher.tube/video/1/x.html", attempt: attempt, extractor: "Generic",
            firstFailure: "Unsupported URL", testResult: "Downloaded 74.8 MB", existing: nil,
            embedURL: URL(string: "https://x-x-x.tube/embed/270856/")))
        #expect(entry.method == "recipe")
        #expect(entry.recipe == .followEmbed)
        #expect(entry.notes?.contains("x-x-x.tube") == true)
    }

    @Test func successfulBuiltInRemembersWhatItObserved() throws {
        let observed = RecipeObservation(embedHost: "mydaddy.cc", titlePattern: "<title>(x)</title>")
        let attempt = SiteLearner.Attempt(label: "reading video sources", recipe: .smartScan)
        let entry = try #require(SiteLearner.workingEntry(
            url: "https://hqporner.com/hdporn/1-x.html", attempt: attempt, extractor: "Generic",
            firstFailure: "Unsupported URL", testResult: "Downloaded", existing: nil,
            embedURL: URL(string: "https://mydaddy.cc/video/abc/"), observed: observed))
        let recipe = try #require(entry.recipe)
        #expect(recipe.base == "smartScan")
        #expect(recipe.embed?.match == #"mydaddy\.cc/"#)
        #expect(recipe.title == "<title>(x)</title>")
        #expect(recipe.unescape == true && recipe.media == .sources)
        #expect(entry.notes?.contains("Remembered from the download: the player iframe (mydaddy.cc/)") == true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        #expect(String(decoding: try encoder.encode(recipe), as: UTF8.self)
                == #"{"base":"smartScan","embed":{"match":"mydaddy\\.cc/"},"title":"<title>(x)</title>"}"#)

        let pattern = Recipe.playerConfig.patterns![0]
        let config = SiteLearner.specialized(.playerConfig, with: RecipeObservation(matchedPattern: pattern))
        #expect(config.pattern == pattern)
        #expect(SiteLearner.specialized(.followEmbed, with: RecipeObservation()) == .followEmbed)

        let saved = SiteLearner.specialized(recipe, with: RecipeObservation(embedHost: "other.cc", titlePattern: "y"))
        #expect(saved == recipe)
    }

    @Test func sharedPlayersNeedTwoWorkingSites() {
        func site(_ name: String, _ match: String?, status: String = "working") -> SiteConfig {
            SiteConfig(id: name, name: name, match: [name], method: "recipe", status: status,
                       recipe: Recipe(base: "smartScan", embed: .init(match: match), unescape: true, media: .sources))
        }
        let sites = [site("b.com", #"mydaddy\.cc/"#), site("a.com", #"mydaddy\.cc/video/"#), site("c.com", #"x-x-x\.tube/embed/"#),
                     site("d.com", #"x-x-x\.tube/"#, status: "broken"), site("e.com", nil)]
        #expect(SiteLearner.sharedPlayers(in: sites) == [.init(host: "mydaddy.cc", siteNames: ["a.com", "b.com"])])
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
        #expect(!rewritten.contains(#""followEmbed" : true"#))
        #expect(!rewritten.contains(#""method" : "embed""#))
        #expect(rewritten.contains(#""base" : "followEmbed""#))
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
        #expect(SitesView.methodLabel(for: sites[0]) == "builtin")
        let recipeSite = SiteConfig(id: "h", name: "H", match: ["h.com"], method: "recipe", status: "working",
                                    recipe: Recipe(base: "smartScan", embed: .init(match: "x"), unescape: true, media: .sources))
        #expect(SitesView.methodLabel(for: recipeSite) == "recipe (smartScan)")
    }

    @Test func classifiesFailures() {
        #expect(SiteLearner.classify("Unable to download webpage: <urlopen error [Errno 8] nodename nor servname provided>") == .local)
        #expect(SiteLearner.classify("This video is DRM protected") == .drm)
        #expect(SiteLearner.classify("ERROR: [Piracy] This website is no longer supported since it has been determined to be primarily used for piracy.") == .piracy)
        #expect(SiteLearner.classify("[youtube] abc: Private video. Sign in if you've been granted access") == .itemSpecific)
        #expect(SiteLearner.classify("Unsupported URL: https://example.com/") == .site)
        #expect(SiteLearner.classify("HTTP Error 403: Forbidden") == .site)
    }

    @Test func workingEntryRecordsDownloadRecipeAndWhy() throws {
        let attempt = SiteLearner.Attempt(label: "browser impersonation", recipe: SiteLearner.impersonate)
        let entry = try #require(SiteLearner.workingEntry(
            url: "https://www.example.com/v/1", attempt: attempt, extractor: "Generic",
            firstFailure: "HTTP Error 403: Forbidden", testResult: "Downloaded 1 MB", existing: nil,
            date: Date(timeIntervalSince1970: 1_793_000_000)))
        #expect(entry.id == "example-com")
        #expect(entry.match == ["example.com"])
        #expect(entry.method == "recipe")
        #expect(entry.status == "working")
        #expect(entry.recipe == SiteLearner.impersonate)
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

    @Test func previewClipIsNotTheVideo() {
        let clip = Data(#"{"streams":[{"codec_type":"video","codec_name":"h264","width":640,"height":360}],"format":{"duration":"0.6"}}"#.utf8)
        let result = MediaProbe.summarize(json: clip, size: 40_000)
        #expect(!result.playable)
        #expect(result.summary.contains("preview"))
        let song = Data(#"{"streams":[{"codec_type":"audio","codec_name":"aac"}],"format":{"duration":"3.0"}}"#.utf8)
        #expect(MediaProbe.summarize(json: song, size: 40_000).playable)
    }

    @Test func parsesExtractorLine() {
        #expect(YtDlpOutputParser.parse(line: "SIPHON-EXTRACTOR Generic|clip-1|NA")
            == .extractor(name: "Generic", videoID: "clip-1", inPlaylist: false))
        #expect(YtDlpOutputParser.parse(line: "SIPHON-EXTRACTOR Youtube|abc|3")
            == .extractor(name: "Youtube", videoID: "abc", inPlaylist: true))
    }
}
