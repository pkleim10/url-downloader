import Foundation
import Testing
@testable import Siphon

struct RecipeTests {
    /// The mydaddy.cc player writes its <video> from a JavaScript string with escaped quotes and slashes.
    static let escapedPlayer = #"""
    <script>document.getElementById('player').innerHTML = "<video id=\"v\" poster=\"\/\/s1.bigcdn.cc\/p.jpg\" src=\"\" controls><source src=\"\/\/s12.bigcdn.cc\/pubs\/abc\/360.mp4\" title=\"360p\" type=\"video\/mp4\"><source src=\"\/\/s12.bigcdn.cc\/pubs\/abc\/720.mp4\" title=\"720p60\" type=\"video\/mp4\"><source src=\"\/\/s12.bigcdn.cc\/pubs\/abc\/1080.mp4\" title=\"1080p60\" type=\"video\/mp4\"><source src=\"\/\/s12.bigcdn.cc\/pubs\/abc\/1080.mp4\" title=\"1080p60\" type=\"video\/mp4\"><\/video>";</script>
    """#
    static let embedBase = URL(string: "https://mydaddy.cc/video/abc/")!

    @Test func unescapedSourcesAreFoundAndDeduplicated() {
        let sources = RecipeRunner.sources(in: RecipeRunner.unescape(Self.escapedPlayer), base: Self.embedBase)
        #expect(sources.map(\.height) == [360, 720, 1080])
        #expect(sources.last?.url.absoluteString == "https://s12.bigcdn.cc/pubs/abc/1080.mp4")
        #expect(sources.last?.label == "1080p60")
    }

    @Test func escapedMarkupYieldsNothingUntilUnescaped() {
        #expect(RecipeRunner.sources(in: Self.escapedPlayer, base: Self.embedBase).isEmpty)
    }

    @Test func choosesTallestWithinQuality() {
        let sources = RecipeRunner.sources(in: RecipeRunner.unescape(Self.escapedPlayer), base: Self.embedBase)
        #expect(RecipeRunner.choose(sources, quality: .best)?.height == 1080)
        #expect(RecipeRunner.choose(sources, quality: .configFile)?.height == 1080)
        #expect(RecipeRunner.choose(sources, quality: .p720)?.height == 720)
        let onlyTall = sources.filter { $0.height == 1080 }
        #expect(RecipeRunner.choose(onlyTall, quality: .p720)?.height == 1080)
    }

    @Test func heightFromFileNameWhenUnlabelled() {
        let html = #"<video src="/media/clip_480p.mp4"></video>"#
        let sources = RecipeRunner.sources(in: html, base: URL(string: "https://example.com/v/1")!)
        #expect(sources.first?.height == 480)
        #expect(sources.first?.url.absoluteString == "https://example.com/media/clip_480p.mp4")
    }

    @Test func iframeMatchingPattern() {
        let page = URL(string: "https://hqporner.com/hdporn/128512-wide_and_wet.html")!
        let html = #"""
        <iframe src="https://ads.example/banner"></iframe>
        <iframe width="560" src="//mydaddy.cc/video/abc/" allowfullscreen></iframe>
        """#
        #expect(RecipeRunner.iframe(matching: #"mydaddy\.cc/video/"#, in: html, base: page)?.absoluteString
                == "https://mydaddy.cc/video/abc/")
        #expect(RecipeRunner.iframe(matching: #"nothing\.here"#, in: html, base: page) == nil)
    }

    @Test func titleAndPageID() {
        let html = "<html><head><title>Wide And Wet - HQporner.com</title>"
        #expect(RecipeRunner.firstMatch(#"<title>([^<]+?)\s*-\s*HQporner"#, in: html) == "Wide And Wet")
        #expect(RecipeRunner.defaultTitle(in: #"<meta property="og:title" content="Tom &amp; Jerry">"#) == "Tom & Jerry")
        #expect(RecipeRunner.pageID(URL(string: "https://hqporner.com/hdporn/128512-wide_and_wet.html")!) == "128512-wide_and_wet")
    }

    @Test func argumentsEscapeBackslashesForYtDlp() {
        let resolution = RecipeResolution(
            url: URL(string: "https://cdn.example/1.mp4")!, referer: "https://example.com/v/1",
            title: #"A\B 100%"#, videoID: "v-1")
        #expect(RecipeRunner.arguments(for: resolution) == [
            "--add-headers", "Referer:https://example.com/v/1",
            "--replace-in-metadata", "title", "^.*$", #"A\\B 100%"#,
            "--replace-in-metadata", "id", "^.*$", "v-1",
        ])
    }

    @Test func patternFindsURLInEscapedPlayerConfig() {
        let html = #"var playerConfig = { sources: {"hlsAuto":"https:\/\/cdn.example.com\/key=a,end=1\/multi=854x480:x\/_TPL_.mp4"}, aspectRatio: '852/480' };"#
        let pattern = #""hlsAuto"\s*:\s*"([^"]+)""#
        #expect(RecipeRunner.firstMatch(pattern, in: RecipeRunner.unescape(html))
                == "https://cdn.example.com/key=a,end=1/multi=854x480:x/_TPL_.mp4")
    }

    @Test func recognisesCloudflareChallenge() {
        #expect(BrowserFetch.isChallenge("<html><head><title>Just a moment...</title>"))
        #expect(BrowserFetch.isChallenge(#"<script src="https://challenges.cloudflare.com/turnstile/v0/api.js"></script>"#))
        #expect(!BrowserFetch.isChallenge("<html><title>Skinny ts takes bbc | aShemaleTube</title>" + String(repeating: "x", count: 30_000)
                                          + "challenges.cloudflare.com"))
    }

    @Test func decodesFetchAndPattern() {
        let json = #"{"sites":[{"id":"a","name":"A","match":["a.com"],"method":"recipe","status":"working","recipe":{"fetch":"browser","unescape":true,"media":"pattern","pattern":"\"hlsAuto\":\"([^\"]+)\""}}]}"#
        let recipe = SiteRegistry.decode(Data(json.utf8)).first?.recipe
        #expect(recipe?.fetch == .browser)
        #expect(recipe?.media == .pattern)
        #expect(recipe?.pattern == #""hlsAuto":"([^"]+)""#)
        #expect(recipe?.summary.hasPrefix("Fetch pages as desktop Chrome") == true)
    }

    @Test func baseFillsMissingFieldsAndEncodesOnlyDifferences() throws {
        let json = #"{"base":"smartScan","embed":{"match":"mydaddy\\.cc/video/"},"title":"x(y)"}"#
        let recipe = try JSONDecoder().decode(Recipe.self, from: Data(json.utf8))
        #expect(recipe.media == .sources)
        #expect(recipe.unescape == true)
        #expect(recipe.embed?.match == #"mydaddy\.cc/video/"#)
        #expect(recipe != .smartScan)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        #expect(String(decoding: try encoder.encode(recipe), as: UTF8.self) == json)
        #expect(String(decoding: try encoder.encode(Recipe.followEmbed), as: UTF8.self) == #"{"base":"followEmbed"}"#)
        #expect(recipe.summary.hasPrefix(#"Built-in "read the player's video sources": open the player iframe"#))
    }

    @Test func writtenOutBuiltInIsRecognised() throws {
        let legacy = try JSONDecoder().decode(Recipe.self, from: Data(#"{"embed":{},"media":"ytdlp"}"#.utf8))
        #expect(legacy == .followEmbed)
        #expect(legacy.base == "followEmbed")
        #expect((try? JSONDecoder().decode(Recipe.self, from: Data(#"{"base":"nope"}"#.utf8))) == nil)
    }

    @Test func playerConfigFindsCommonKeysAndSkipsNonVideo() throws {
        func found(_ html: String) -> String? {
            let candidates = Recipe.playerConfig.patterns ?? []
            let text = RecipeRunner.unescape(html)
            return candidates.lazy.compactMap { RecipeRunner.firstMatch($0, in: text) }.first
        }
        #expect(found(#"sources: {"hlsAuto":"https:\/\/cdn.example.com\/key=a,end=1\/_TPL_.mp4"}"#)
                == "https://cdn.example.com/key=a,end=1/_TPL_.mp4")
        #expect(found(#"jwplayer("p").setup({ image: "https://cdn.example.com/t.jpg", file: "https://cdn.example.com/v/master.m3u8?t=1" });"#)
                == "https://cdn.example.com/v/master.m3u8?t=1")
        #expect(found(#"{"poster":"https://cdn.example.com/t.jpg","src":"https://cdn.example.com/thumb.jpg","url":"https://example.com/v/2"}"#) == nil)
        #expect(found(#"var flashvars = { video_url: 'https://cdn.example.com/get_file/1/abc/720.mp4' };"#)
                == "https://cdn.example.com/get_file/1/abc/720.mp4")
    }

    @Test func titleTrimRemovesSiteNameFromTheEnd() throws {
        let hq = URL(string: "https://hqporner.com/hdporn/1-x.html")!
        let trim = try #require(RecipeRunner.titleTrim(in: "<html><title>Wide And Wet - HQporner.com</title>", page: hq))
        #expect(trim.title == "Wide And Wet")
        #expect(RecipeRunner.firstMatch(trim.pattern, in: "<title>Other Video - HQporner.com</title>") == "Other Video")

        let dashes = try #require(RecipeRunner.titleTrim(in: "<title>Part 1 - The Return | HQporner.com</title>", page: hq))
        #expect(dashes.title == "Part 1 - The Return")

        let siteName = #"<meta property="og:site_name" content="aShemaleTube" /><title>Skinny ts takes bbc | aShemaleTube</title>"#
        #expect(RecipeRunner.titleTrim(in: siteName, page: URL(string: "https://www.ashemaletube.com/videos/1/x/")!)?.title
                == "Skinny ts takes bbc")

        #expect(RecipeRunner.titleTrim(in: "<title>Just A Title</title>", page: hq) == nil)
    }

    @Test func decodesSiteEntryAndMapsFollowEmbed() throws {
        let json = #"""
        {"sites":[
          {"id":"h","name":"H","match":["hqporner.com"],"method":"recipe","status":"working",
           "recipe":{"embed":{"match":"mydaddy\\.cc/video/","referer":true},"unescape":true,"media":"sources","title":"x(y)"}},
          {"id":"e","name":"E","match":["e.com"],"method":"embed","status":"working","followEmbed":true}
        ]}
        """#
        let sites = SiteRegistry.decode(Data(json.utf8))
        #expect(sites[0].recipe == Recipe(embed: .init(match: #"mydaddy\.cc/video/"#, referer: true),
                                          unescape: true, media: .sources, title: "x(y)"))
        #expect(sites[1].recipe == .followEmbed)
        #expect(sites[1].method == "recipe")
        #expect(sites[0].recipe?.summary.contains("undo JavaScript escaping") == true)
    }
}
