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

    @Test func decodesSiteEntryAndMapsFollowEmbed() throws {
        let json = #"""
        {"sites":[
          {"id":"h","name":"H","match":["hqporner.com"],"method":"recipe","status":"working",
           "recipe":{"embed":{"match":"mydaddy\\.cc/video/","referer":true},"unescape":true,"media":"sources","title":"x(y)"}},
          {"id":"e","name":"E","match":["e.com"],"method":"embed","status":"working","followEmbed":true}
        ]}
        """#
        let sites = SiteRegistry.decode(Data(json.utf8))
        #expect(sites[0].effectiveRecipe == Recipe(embed: .init(match: #"mydaddy\.cc/video/"#, referer: true),
                                                   unescape: true, media: .sources, title: "x(y)"))
        #expect(sites[1].effectiveRecipe == .followEmbed)
        #expect(sites[0].effectiveRecipe?.summary.contains("undo JavaScript escaping") == true)
    }
}
