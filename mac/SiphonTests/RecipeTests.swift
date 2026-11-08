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
        #expect(recipe?.pattern == #""hlsAuto":"([^"]+)""#)    }

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
        #expect(String(decoding: try encoder.encode(Recipe.followEmbed), as: UTF8.self) == #"{"base":"followEmbed"}"#)    }

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

    @Test func detailsListOnlyWhatDiffersFromTheBuiltIn() throws {
        #expect(Recipe.followEmbed.details.isEmpty)
        #expect(Recipe.playerConfig.details.isEmpty)
        #expect(Recipe.builtIns.allSatisfy { !$0.description.contains("custom") })
        #expect(Recipe(media: .ytdlp).description.hasPrefix("A custom recipe"))

        let hq = URL(string: "https://hqporner.com/hdporn/1-x.html")!
        let trim = try #require(RecipeRunner.titleTrim(in: "<title>Wide And Wet - HQporner.com</title>", page: hq))
        let learned = SiteLearner.specialized(.smartScan, with: RecipeObservation(embedHost: "mydaddy.cc", titlePattern: trim.pattern))
        #expect(learned.details.map(\.label) == ["Player", "Title"])
        #expect(learned.details[0].value == "iframe matching mydaddy.cc/")
        #expect(learned.details[1].value == #"remove "hqporner" from the end of the page title"#)

        let config = SiteLearner.specialized(.playerConfig, with: RecipeObservation(matchedPattern: Recipe.playerConfig.patterns![0]))
        #expect(config.details.map(\.value) == ["player key hlsAuto"])
        #expect(Recipe.playerKeys(in: Recipe.playerConfig.patterns![1])?.hasPrefix("hls, hlsUrl") == true)

        let custom = Recipe(fetch: .browser, unescape: true, media: .pattern, pattern: #""v"\s*:\s*"([^"]+)""#, title: "<h1>(.+)</h1>")
        #expect(custom.details.map(\.label) == ["Fetch", "Unescape", "Video", "Video key", "Title"])
        #expect(custom.details.last?.value == "<h1>(.+)</h1>")
    }

    @Test func jsonSourceListPrefersH264AtEqualHeight() {
        let html = #"""
        {"codec":"av1","srcSet":[{"src":"https://cdn.example/v_av1_2160.mp4?e=1","type":"video/mp4; codecs=\"av01.0.05M.08\"","label":"2160p"},{"src":"https://cdn.example/v_av1_1080.mp4","type":"video/mp4; codecs=\"av01.0.05M.08\"","label":"1080p"}]},
        {"codec":"h264","srcSet":[{"src":"https://cdn.example/v_h264_2160.mp4?e=1","type":"video/mp4; codecs=\"avc1.4d4015\"","label":"2160p"},{"src":"https://cdn.example/v_h264_1080.mp4","type":"video/mp4; codecs=\"avc1.4d4015\"","label":"1080p"}]}
        """#
        let sources = RecipeRunner.sources(in: RecipeRunner.unescape(html), base: URL(string: "https://example.com/")!)
        #expect(sources.count == 4)
        #expect(RecipeRunner.choose(sources, quality: .best)?.url.absoluteString == "https://cdn.example/v_h264_2160.mp4?e=1")
        #expect(RecipeRunner.choose(sources, quality: .p1080)?.url.absoluteString == "https://cdn.example/v_h264_1080.mp4")
    }

    @Test func qualityWordsRankSourcesOfUnknownHeight() {
        let html = #"""
        <source src="https://cdn.example/1_360p.mp4/?br=529" title="LQ" /><source src="https://cdn.example/1_hq.mp4/?br=1996" title="HQ" />
        """#
        let sources = RecipeRunner.sources(in: html, base: URL(string: "https://example.com/")!)
        #expect(RecipeRunner.choose(sources, quality: .best)?.label == "HQ")
        #expect(RecipeRunner.choose(sources, quality: .p720)?.label == "HQ")
        let words = #"<source src="https://cdn.example/a.mp4" label="low"><source src="https://cdn.example/b.mp4" label="high">"#
        #expect(RecipeRunner.choose(RecipeRunner.sources(in: words, base: URL(string: "https://example.com/")!), quality: .best)?.label == "high")
    }

    @Test func heightIgnoresIDsInFileNames() {
        #expect(RecipeRunner.height(in: URL(string: "https://e.com/get_file/1/a/92000/92390/92390_720p.mp4/?t=1")!) == 720)
        #expect(RecipeRunner.height(in: URL(string: "https://e.com/606000/606293/606293.mp4/")!) == nil)
        #expect(RecipeRunner.height(in: URL(string: "https://e.com/v/480x320_600k_h264_3164625.mp4")!) == nil)
    }

    @Test func playerConfigReadsKVSFlashvarsAndPicksByHeight() {
        let html = #"""
        var flashvars = { video_url: 'https://e.com/get_file/9/a/92000/92390/92390_480p.mp4/?v-acctoken=x', postfix: '_480p.mp4',
        video_alt_url: 'https://e.com/get_file/9/b/92000/92390/92390_720p.mp4/?v-acctoken=y', video_alt_url_text: '720p' };
        """#
        let base = URL(string: "https://e.com/v/1")!
        let found = Recipe.playerConfig.patterns!.lazy.compactMap {
            RecipeRunner.choosePatternMatch($0, in: html, base: base, quality: .best)
        }.first
        #expect(found?.url.absoluteString == "https://e.com/get_file/9/b/92000/92390/92390_720p.mp4/?v-acctoken=y")
        let limited = Recipe.playerConfig.patterns!.lazy.compactMap {
            RecipeRunner.choosePatternMatch($0, in: html, base: base, quality: .p720)
        }.first
        #expect(limited?.height == 720)
    }

    @Test func linkBuildsURLFromPageURLOrPage() throws {
        let page = URL(string: "https://www.iceporn.com/video/7418363/some-title")!
        let api = Recipe.Link(find: #"/video/(\d+)"#, url: "https://www.iceporn.com/player_config_json/?vid=$1")
        #expect(RecipeRunner.linkURL(api, page: page, html: "")?.absoluteString
                == "https://www.iceporn.com/player_config_json/?vid=7418363")
        let embed = Recipe.Link(find: #"vxxx\.com/embed-(\d+)"#, url: "https://vxxx.com/video-$1/")
        #expect(RecipeRunner.linkURL(embed, page: page, html: #"<iframe src="https://vxxx.com/embed-1721143/?c=1">"#)?.absoluteString
                == "https://vxxx.com/video-1721143/")
        #expect(RecipeRunner.linkURL(embed, page: page, html: "no player") == nil)
        let fixed = Recipe.Link(url: "/service/index.json?device=desktop")
        #expect(RecipeRunner.linkURL(fixed, page: page, html: "")?.absoluteString == "https://www.iceporn.com/service/index.json?device=desktop")

        let json = #"{"link":{"find":"vxxx\\.com/embed-(\\d+)","url":"https://vxxx.com/video-$1/"},"media":"ytdlp"}"#
        let recipe = try JSONDecoder().decode(Recipe.self, from: Data(json.utf8))
        #expect(recipe.link == embed)
        #expect(recipe.details.first?.label == "Link")
        let encoded = String(decoding: try JSONEncoder().encode(recipe), as: UTF8.self)
        #expect(encoded.contains("\"link\""))
    }

    @Test func pageSourcesIsABuiltIn() throws {
        let decoded = try JSONDecoder().decode(Recipe.self, from: Data(#"{"unescape":true,"media":"sources"}"#.utf8))
        #expect(decoded == .pageSources)
        #expect(Recipe.builtIn(named: "pageSources") == .pageSources)
    }

    @Test func scriptBuiltIframesAreSkipped() {
        let page = URL(string: "https://zbporn.com/videos/1/x/")!
        let html = #"<div class="player"><iframe src="https://ads.example/9/?zone=44'+(promo ? '&promo='+promo.pop() : '')+'" allowfullscreen></iframe></div>"#
        #expect(EmbedFinder.find(in: html, pageURL: page) == nil)
    }

    @Test func formatPresetsPreferLabelledHighOnlyWithoutHeights() {
        let format = QualityPreset.p1080.formatArguments
        #expect(format.first == "-f")
        #expect(format.last?.hasPrefix("b[height<?1][format_id~=") == true)
        #expect(format.last?.hasSuffix("bv*[height<=1080]+ba/b[height<=1080]/b") == true)
        #expect(QualityPreset.audioOnly.formatArguments == ["-f", "ba/b", "-x"])
    }

    @Test func plainFilesBeatStreamsAtEqualHeight() {
        #expect(QualityPreset.configFile.sortArguments == ["-S", "res,proto", "--check-formats"])
        #expect(QualityPreset.p720.sortArguments == ["-S", "res,proto", "--check-formats"])
        #expect(QualityPreset.audioOnly.sortArguments.isEmpty)
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
        #expect(SitesView.methodLabel(for: sites[0]) == "recipe (custom)")
        #expect(SitesView.methodLabel(for: sites[1]) == "recipe (followEmbed)")
    }

    @Test func kvsLabelsPickTheOriginalOverAMeasuredLowFile() throws {
        let page = URL(string: "https://zbporn.com/videos/606293/x/")!
        let html = """
        var a = {video_url: 'https://zbporn.com/get_file/28/aa/606000/606293/606293_360p.mp4/?br=651', postfix: '.mp4', video_url_text: 'High Quality'};
        var b = {video_url: 'https://zbporn.com/get_file/28/bb/606000/606293/606293.mp4/?br=750', postfix: '.mp4', video_url_text: 'High Quality',
                 video_alt_url: 'https://zbporn.com/get_file/28/aa/606000/606293/606293_360p.mp4/?br=651', video_alt_url_text: '360p'};
        """
        let files = RecipeRunner.labelledPlayerFiles(in: html, base: page)
        #expect(files.map(\.height) == [360, nil])
        #expect(files.map(\.label) == ["High Quality", "High Quality"])
        let pick = try #require(RecipeRunner.choose(files, quality: .p720))
        #expect(pick.url.absoluteString.contains("/606293.mp4/"))
    }

    @Test func playerDataListsFilesByQualityName() throws {
        let data = #"{"title":"Bibi","files":{"lq":"https://gcdn.example.com/mp4_lq/9e.mp4?md5=a","hq":null,"4k":""}}"#
        let sources = RecipeRunner.sources(in: data, base: URL(string: "https://www.iceporn.com/")!)
        #expect(sources.map(\.label) == ["lq"])
        #expect(RecipeRunner.jsonTitle(in: data) == "Bibi")
        let both = #"{"files":{"lq":"https://c.example/a_lq.mp4","hq":"https://c.example/a_hq.mp4","4k":"https://c.example/a.mp4"}}"#
        let pick = try #require(RecipeRunner.choose(RecipeRunner.sources(in: both, base: URL(string: "https://x.com/")!), quality: .p1080))
        #expect(pick.label == "hq")
        #expect(RecipeRunner.choose(RecipeRunner.sources(in: both, base: URL(string: "https://x.com/")!), quality: .best)?.label == "4k")
    }

    @Test func playerAddressesMapToTheirVideoPages() {
        #expect(RecipeRunner.watchPage(for: URL(string: "https://vxxx.com/embed-1721143/?campaign=10121&source=")!)
                == URL(string: "https://vxxx.com/video-1721143/"))
        #expect(RecipeRunner.watchPage(for: URL(string: "https://example.com/embed/42")!) == URL(string: "https://example.com/video/42/"))
        #expect(RecipeRunner.watchPage(for: URL(string: "https://pornzog.com/embed.php?id=28734086")!) == nil)
    }

    @Test func downloadOnlyRecipesCodeAndDescribeThemselves() throws {
        let recipe = try JSONDecoder().decode(Recipe.self, from: Data(#"{"download":{"impersonate":true,"scanPage":true},"session":true}"#.utf8))
        #expect(recipe.isDownloadOnly)
        #expect(recipe.media == .page)
        #expect(recipe.session == true)
        #expect(recipe.details.map(\.label) == ["Download", "Session"])
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        #expect(String(decoding: try encoder.encode(recipe), as: UTF8.self)
                == #"{"download":{"impersonate":true,"scanPage":true},"session":true}"#)
        #expect(try JSONDecoder().decode(Recipe.self, from: Data(#"{"base":"playerAPI"}"#.utf8)) == .playerAPI)
        #expect(Recipe.playerAPI.details.isEmpty && Recipe.embedPage.details.isEmpty)
    }
}
