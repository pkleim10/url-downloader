import Foundation

/// A declarative way to find a site's video that Siphon carries out itself in Swift.
/// A recipe can only fetch pages and read their text; nothing from a site is ever run.
///
/// Site recipes should start from a built-in (`base`) and set only what differs, so every
/// built-in can serve many sites and the learner can find it on its own:
///
///     "recipe": {
///       "base": "smartScan",
///       "embed": { "match": "mydaddy\\.cc/video/" },
///       "title": "<title>([^<]+?)\\s*-\\s*HQporner"
///     }
struct Recipe: Codable, Equatable {
    struct Embed: Codable, Equatable {
        /// Regex the iframe's src must match; nil picks the most player-like iframe.
        var match: String?
        /// Fetch the iframe with the page as referer (default true).
        var referer: Bool?
    }

    /// Builds the player or data URL from a value on the page, for sites whose player isn't an
    /// iframe or that load their video list from a separate address.
    struct Link: Codable, Equatable {
        /// Regex with one capture group, tried on the page URL and then the page; nil for a fixed `url`.
        var find: String?
        /// The URL, with `$1` replaced by what `find` captured. Fetched with the page as referer;
        /// with `media: ytdlp` it goes to yt-dlp without one, since it's usually the video's own page.
        var url: String
    }

    enum Media: String, Codable {
        /// Hand the (embed) URL to yt-dlp.
        case ytdlp
        /// Collect <source>/<video> URLs and download the best one that fits the quality setting.
        case sources
        /// Take the URL captured by `pattern` (e.g. from a player config in a script) and hand it to yt-dlp.
        case pattern
    }

    enum Fetch: String, Codable {
        /// Plain request, retried through `BrowserFetch` when a bot check answers 403/503 (the default).
        case auto
        /// Always fetch through `BrowserFetch`, for sites known to sit behind a bot check.
        case browser
    }

    /// Name of the built-in this recipe starts from; its own fields override the built-in's.
    var base: String?
    var fetch: Fetch?
    /// Follow the page's player iframe first.
    var embed: Embed?
    /// Go to a URL built from the page instead of an iframe (`embed` is ignored when both are set).
    var link: Link?
    /// Undo JavaScript string escaping (\" \/ \u0026) before reading the markup.
    var unescape: Bool?
    var media: Media
    /// For `media: pattern`: regex with one capture group for the media URL, applied after `unescape`.
    var pattern: String?
    /// For `media: pattern`: more regexes tried in order after `pattern`.
    var patterns: [String]?
    /// Regex with one capture group, applied to the page, for the title.
    var title: String?
    /// Send the page that listed the media as referer when downloading it.
    var mediaReferer: Bool?

    // MARK: - Built-ins

    /// Download the page's player iframe with yt-dlp.
    static let followEmbed = Recipe(base: "followEmbed", embed: Embed(), media: .ytdlp)
    /// Read video sources straight out of the page's player iframe.
    static let smartScan = Recipe(base: "smartScan", embed: Embed(), unescape: true, media: .sources)
    /// Find the video address in the page's player configuration (a script, not markup), trying the
    /// keys common players use from most to least specific. Only stream and video file URLs count,
    /// so thumbnails and page links under the same keys are skipped.
    static let playerConfig = Recipe(
        base: "playerConfig", unescape: true, media: .pattern,
        patterns: [
            #"["']?hlsAuto["']?\s*:\s*["'](https?://[^"'\s]+)["']"#,
            #"["']?(?:hls|hlsUrl|hls_url|hlsSource|m3u8|m3u8Url|m3u8_url)["']?\s*:\s*["'](https?://[^"'\s]+)["']"#,
            #"["']?(?:file|video_url|video_alt_url\d*|videoUrl|video_src|videoSrc|contentUrl|mp4|mp4Url|src|source|url)["']?\s*:\s*["'](https?://[^"'\s]+\.(?:m3u8|mpd|mp4|webm)/?(?:\?[^"'\s]*)?)["']"#,
        ])

    /// Read video sources (tags or a JSON source list) straight out of the page itself.
    static let pageSources = Recipe(base: "pageSources", unescape: true, media: .sources)

    static let builtIns = [followEmbed, smartScan, playerConfig, pageSources]

    static func builtIn(named name: String) -> Recipe? {
        builtIns.first { $0.base == name }
    }

    /// What the recipe does, in a sentence, for the Sites window.
    var description: String {
        switch base {
        case "followEmbed":
            "Finds the video player the page embeds from another site (an iframe) and gives its address to yt-dlp, with the page as referer."
        case "smartScan":
            "Opens the video player the page embeds from another site, undoes the JavaScript escaping in it, reads its video sources, and downloads the best one for the Quality setting."
        case "playerConfig":
            "Reads the page's player settings (a script, not markup) and gives yt-dlp the stream or video file listed under a common player key such as hlsAuto, hls, file or video_url."
        case "pageSources":
            "Reads the video sources listed in the page itself (its <source> tags or a JSON source list), picks the best one for the Quality setting, and gives yt-dlp that file."
        default:
            "A custom recipe; its steps are listed below."
        }
    }

    /// What this recipe sets beyond its built-in, as (label, value) lines for the Sites window.
    /// Recipes without a built-in list every step.
    var details: [(label: String, value: String)] {
        let base = self.base.flatMap(Self.builtIn(named:))
        var lines: [(String, String)] = []
        if fetch != base?.fetch, let fetch {
            lines.append(("Fetch", fetch == .browser ? "always as desktop Chrome (through yt-dlp)" : "plain, as desktop Chrome if blocked"))
        }
        if embed != base?.embed, let embed {
            lines.append(("Player", embed.match.map { "iframe matching \($0.replacingOccurrences(of: "\\", with: ""))" }
                          ?? "most player-like iframe"))
            if embed.referer == false { lines.append(("Referer", "player fetched without the page as referer")) }
        }
        if link != base?.link, let link {
            lines.append(("Link", link.find.map { "\(link.url), with $1 from \($0)" } ?? link.url))
        }
        if unescape != base?.unescape, unescape == true { lines.append(("Unescape", "undo JavaScript escaping")) }
        if media != base?.media {
            let video: String = switch media {
            case .ytdlp: "give yt-dlp the player's URL"
            case .sources: "best <source> for the Quality setting"
            case .pattern: "URL found by a pattern"
            }
            lines.append(("Video", video))
        }
        if pattern != base?.pattern, let pattern {
            lines.append(("Video key", Self.playerKeys(in: pattern).map { "player key \($0)" } ?? pattern))
        }
        if patterns != base?.patterns, let patterns { lines.append(("Video patterns", patterns.joined(separator: "\n"))) }
        if title != base?.title, let title {
            lines.append(("Title", RecipeRunner.trimmedSiteName(in: title).map { "remove \"\($0)\" from the end of the page title" } ?? title))
        }
        if mediaReferer != base?.mediaReferer, mediaReferer == true { lines.append(("Referer", "video fetched with the player as referer")) }
        return lines
    }

    /// "hlsAuto" for `["']?hlsAuto["']?\s*:…`, "hls, hlsUrl, …" for `["']?(?:hls|hlsUrl|…)["']?…`.
    static func playerKeys(in pattern: String) -> String? {
        let prefix = #"["']?"#
        guard pattern.hasPrefix(prefix) else { return nil }
        let rest = pattern.dropFirst(prefix.count)
        if rest.hasPrefix("(?:"), let end = rest.firstIndex(of: ")") {
            return rest[rest.index(rest.startIndex, offsetBy: 3)..<end].replacingOccurrences(of: "|", with: ", ")
        }
        let key = rest.prefix { $0.isLetter || $0.isNumber || $0 == "_" }
        return key.isEmpty ? nil : String(key)
    }

    // MARK: - Coding

    private enum CodingKeys: String, CodingKey {
        case base, fetch, embed, link, unescape, media, pattern, patterns, title, mediaReferer
    }

    init(base: String? = nil, fetch: Fetch? = nil, embed: Embed? = nil, link: Link? = nil, unescape: Bool? = nil,
         media: Media, pattern: String? = nil, patterns: [String]? = nil, title: String? = nil, mediaReferer: Bool? = nil) {
        self.base = base
        self.fetch = fetch
        self.embed = embed
        self.link = link
        self.unescape = unescape
        self.media = media
        self.pattern = pattern
        self.patterns = patterns
        self.title = title
        self.mediaReferer = mediaReferer
    }

    /// Fields missing from the JSON come from the built-in named by `base`. A recipe written out
    /// in full that equals a built-in is recognised as that built-in.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let baseName = try c.decodeIfPresent(String.self, forKey: .base)
        let base = try baseName.map { name in
            guard let builtIn = Self.builtIn(named: name) else {
                throw DecodingError.dataCorruptedError(forKey: .base, in: c, debugDescription: "Unknown built-in recipe \(name)")
            }
            return builtIn
        }
        self.base = baseName
        fetch = try c.decodeIfPresent(Fetch.self, forKey: .fetch) ?? base?.fetch
        embed = try c.decodeIfPresent(Embed.self, forKey: .embed) ?? base?.embed
        link = try c.decodeIfPresent(Link.self, forKey: .link) ?? base?.link
        unescape = try c.decodeIfPresent(Bool.self, forKey: .unescape) ?? base?.unescape
        guard let media = try c.decodeIfPresent(Media.self, forKey: .media) ?? base?.media else {
            throw DecodingError.keyNotFound(CodingKeys.media, .init(codingPath: c.codingPath, debugDescription: "A recipe needs media or base"))
        }
        self.media = media
        pattern = try c.decodeIfPresent(String.self, forKey: .pattern) ?? base?.pattern
        patterns = try c.decodeIfPresent([String].self, forKey: .patterns) ?? base?.patterns
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? base?.title
        mediaReferer = try c.decodeIfPresent(Bool.self, forKey: .mediaReferer) ?? base?.mediaReferer
        if baseName == nil, let same = Self.builtIns.first(where: { $0.withoutBase == self }) {
            self.base = same.base
        }
    }

    /// Writes `base` plus only the fields that differ from it.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        let base = self.base.flatMap(Self.builtIn(named:))
        try c.encodeIfPresent(self.base, forKey: .base)
        func put<T: Encodable & Equatable>(_ value: T?, _ inBase: T?, _ key: CodingKeys) throws {
            if let value, base == nil || value != inBase { try c.encode(value, forKey: key) }
        }
        try put(fetch, base?.fetch, .fetch)
        try put(embed, base?.embed, .embed)
        try put(link, base?.link, .link)
        try put(unescape, base?.unescape, .unescape)
        try put(media, base?.media, .media)
        try put(pattern, base?.pattern, .pattern)
        try put(patterns, base?.patterns, .patterns)
        try put(title, base?.title, .title)
        try put(mediaReferer, base?.mediaReferer, .mediaReferer)
    }

    private var withoutBase: Recipe {
        var copy = self
        copy.base = nil
        return copy
    }
}

/// What a recipe resolved to: the URL to give yt-dlp and how to label the download.
struct RecipeResolution: Equatable {
    var url: URL
    var referer: String?
    var title: String?
    /// Stable id for the download (the page's own id), so files from different pages never share one.
    var videoID: String?
    var sourceLabel: String?
    /// The player iframe the recipe followed, if any.
    var embedURL: URL?
    /// What worked on this page, for the learner to remember (see `SiteLearner.specialized`).
    var observed = RecipeObservation()
}

struct RecipeObservation: Equatable {
    /// Host of the player iframe that was picked by scoring rather than by `embed.match`.
    var embedHost: String?
    /// The entry of `patterns` that found the media URL, when the recipe had no `pattern` of its own.
    var matchedPattern: String?
    /// A `title` regex that strips the site's name from the page title, checked on this page.
    var titlePattern: String?
}

struct RecipeSource: Equatable {
    var url: URL
    var label: String?
    var height: Int?
    /// False for AV1/HEVC sources, which lose ties to H.264.
    var compatible = true
}

enum RecipeError: LocalizedError, Equatable {
    case pageUnavailable(String)
    case noEmbed
    case noLink
    case noSources

    var errorDescription: String? {
        switch self {
        case .pageUnavailable(let detail): "Couldn't load the page: \(detail)"
        case .noEmbed: "No embedded player found on the page"
        case .noLink: "The value the recipe's link needs isn't on the page"
        case .noSources: "No video sources found in the player"
        }
    }
}

enum RecipeRunner {
    static func resolve(page: URL, recipe: Recipe, quality: QualityPreset) async throws -> RecipeResolution {
        let mode = recipe.fetch ?? .auto
        let pageHTML = try await fetch(page, referer: nil, mode: mode)
        var observed = RecipeObservation()
        var title = recipe.title.flatMap { firstMatch($0, in: pageHTML) }.map(cleanTitle)
        if title == nil, recipe.media != .ytdlp {
            let fallback = defaultTitle(in: pageHTML)
            if let trim = titleTrim(in: pageHTML, page: page),
               fallback.map({ $0.count > trim.title.count && $0.hasPrefix(trim.title) }) ?? true {
                observed.titlePattern = trim.pattern
                title = trim.title
            } else {
                title = fallback
            }
        }
        let videoID = pageID(page)

        var html = pageHTML
        var base = page
        var embedURL: URL?
        if let link = recipe.link {
            guard let found = linkURL(link, page: page, html: pageHTML) else { throw RecipeError.noLink }
            embedURL = found
            if recipe.media != .ytdlp {
                html = try await fetch(found, referer: page.absoluteString, mode: mode, accept: dataAccept)
                base = found
            }
        } else if let embed = recipe.embed {
            let found = embed.match.map { iframe(matching: $0, in: pageHTML, base: page) }
                ?? EmbedFinder.find(in: pageHTML, pageURL: page)
            guard let found else { throw RecipeError.noEmbed }
            embedURL = found
            if embed.match == nil { observed.embedHost = found.host?.lowercased() }
            if recipe.media != .ytdlp {
                html = try await fetch(found, referer: embed.referer == false ? nil : page.absoluteString, mode: mode)
                base = found
            }
        }
        if recipe.unescape == true { html = unescape(html) }

        switch recipe.media {
        case .ytdlp:
            guard let embedURL else { throw RecipeError.noEmbed }
            return RecipeResolution(url: embedURL, referer: recipe.link == nil ? page.absoluteString : nil, title: title, videoID: nil,
                                    embedURL: embedURL, observed: observed)
        case .sources:
            guard let source = choose(sources(in: html, base: base), quality: quality) else { throw RecipeError.noSources }
            return RecipeResolution(
                url: source.url, referer: recipe.mediaReferer == true ? base.absoluteString : nil,
                title: title, videoID: videoID, sourceLabel: source.label, embedURL: embedURL, observed: observed)
        case .pattern:
            let candidates = (recipe.pattern.map { [$0] } ?? []) + (recipe.patterns ?? [])
            var found: RecipeSource?
            for candidate in candidates {
                if let source = choosePatternMatch(candidate, in: html, base: base, quality: quality) {
                    found = source
                    if recipe.pattern == nil { observed.matchedPattern = candidate }
                    break
                }
            }
            guard let found else { throw RecipeError.noSources }
            return RecipeResolution(
                url: found.url, referer: recipe.mediaReferer == true ? base.absoluteString : nil,
                title: title, videoID: videoID, sourceLabel: found.label, embedURL: embedURL, observed: observed)
        }
    }

    static let titleSeparators = "-|–—:·•"
    private static let titleTrimPrefix = #"<title[^>]*>\s*([^<]*[^<\s])\s*["#
        + NSRegularExpression.escapedPattern(for: titleSeparators) + #"]\s*[^"#
        + NSRegularExpression.escapedPattern(for: titleSeparators) + "<]*"
    private static let titleTrimSuffix = #"[^<]*</title>"#

    /// The site name a `titleTrim` pattern removes, or nil for any other title regex.
    static func trimmedSiteName(in pattern: String) -> String? {
        guard pattern.hasPrefix(titleTrimPrefix), pattern.hasSuffix(titleTrimSuffix),
              pattern.count > titleTrimPrefix.count + titleTrimSuffix.count else { return nil }
        let escaped = pattern.dropFirst(titleTrimPrefix.count).dropLast(titleTrimSuffix.count)
        return escaped.replacingOccurrences(of: #"\\(.)"#, with: "$1", options: .regularExpression)
    }

    /// A `title` regex that removes the site's name (og:site_name, or the domain's main label)
    /// from the end of the page's <title>, and the title it gives on this page. Keeps everything
    /// before the last separator, so titles that contain a separator themselves stay whole.
    static func titleTrim(in html: String, page: URL) -> (pattern: String, title: String)? {
        guard let raw = firstMatch(#"<title[^>]*>([^<]+)</title>"#, in: html).map(cleanTitle), !raw.isEmpty else { return nil }
        var names: [String] = []
        if let site = firstMatch(#"<meta[^>]+property=["']og:site_name["'][^>]+content=["']([^"']+)"#, in: html) {
            names.append(cleanTitle(site))
        }
        if let host = page.host?.lowercased() {
            let labels = host.split(separator: ".").map(String.init)
            if labels.count >= 2 { names.append(labels[labels.count - 2]) }
        }
        for name in names where name.count >= 3 {
            let pattern = titleTrimPrefix + NSRegularExpression.escapedPattern(for: name) + titleTrimSuffix
            if let title = firstMatch(pattern, in: html).map(cleanTitle), !title.isEmpty, title.count < raw.count {
                return (pattern, title)
            }
        }
        return nil
    }

    /// yt-dlp options that apply a resolution: referer, and title/id when the URL is a bare file.
    static func arguments(for resolution: RecipeResolution) -> [String] {
        var args: [String] = []
        if let referer = resolution.referer { args += ["--add-headers", "Referer:\(referer)"] }
        if let title = resolution.title, !title.isEmpty {
            args += ["--replace-in-metadata", "title", "^.*$", regexReplacement(title)]
        }
        if let id = resolution.videoID, !id.isEmpty {
            args += ["--replace-in-metadata", "id", "^.*$", regexReplacement(id)]
        }
        return args
    }

    // MARK: - Parsing

    static func iframe(matching pattern: String, in html: String, base: URL) -> URL? {
        guard let pattern = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        return iframeSources(in: html, base: base).first { url in
            let text = url.absoluteString
            return pattern.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
        }
    }

    static func iframeSources(in html: String, base: URL) -> [URL] {
        tags("iframe", in: html).compactMap { tag in
            (attribute("src", in: tag) ?? attribute("data-src", in: tag)).flatMap { resolve($0, base: base) }
        }
    }

    /// <source> tags, any <video src=...>, and JSON source lists (`{"src": …, "label": "720p"}`),
    /// deduplicated, with the height read from the label or URL.
    static func sources(in html: String, base: URL) -> [RecipeSource] {
        var seen = Set<String>()
        var result: [RecipeSource] = []
        for tag in tags("source", in: html) + tags("video", in: html) {
            guard let src = attribute("src", in: tag), let url = resolve(src, base: base),
                  seen.insert(url.absoluteString).inserted else { continue }
            let label = attribute("title", in: tag) ?? attribute("label", in: tag) ?? attribute("res", in: tag)
                ?? attribute("size", in: tag) ?? attribute("data-quality", in: tag)
            let height = label.flatMap { firstMatch(#"(\d{3,4})"#, in: $0) }.flatMap { Int($0) } ?? height(in: url)
            result.append(RecipeSource(url: url, label: label, height: height, compatible: isCompatible(tag)))
        }
        for object in matches(jsonSourcePattern, in: html, group: 0) {
            guard let src = firstMatch(#""(?:src|file|url|link)"\s*:\s*"(https?://[^"]+)""#, in: object),
                  let url = resolve(src, base: base), seen.insert(url.absoluteString).inserted else { continue }
            let label = firstMatch(#""(?:label|res|quality|name|height)"\s*:\s*"?([^",}]+)"#, in: object)
            let height = label.flatMap { firstMatch(#"(\d{3,4})"#, in: $0) }.flatMap { Int($0) } ?? height(in: url)
            result.append(RecipeSource(url: url, label: label, height: height, compatible: isCompatible(object)))
        }
        return result
    }

    /// A JSON object (no nesting) that names a video file or stream under src/file/url/link.
    private static let jsonSourcePattern =
        #"\{[^{}]*"(?:src|file|url|link)"\s*:\s*"https?://[^"]+\.(?:mp4|webm|m3u8)[^"]*"[^{}]*\}"#

    /// The tallest source within the quality setting's limit; the tallest overall if none fit.
    /// A source of unknown height labelled HQ/high/HD ranks above every measured one (players
    /// that label sources that way give the low one its height, e.g. "LQ" for `_360p.mp4`).
    /// Among equal heights, H.264 beats AV1 and HEVC, which not every Mac player decodes.
    static func choose(_ sources: [RecipeSource], quality: QualityPreset) -> RecipeSource? {
        let limit: Int? = switch quality {
        case .p2160: 2160
        case .p1440: 1440
        case .p1080: 1080
        case .p720: 720
        case .configFile, .best, .audioOnly: nil
        }
        func rank(_ source: RecipeSource) -> Int {
            source.height ?? (labelledHigh(source.label) ? 100_000 : labelledLow(source.label) ? 1 : 0)
        }
        let ranked = sources.enumerated().sorted { a, b in
            let (ra, rb) = (rank(a.element), rank(b.element))
            if ra != rb { return ra > rb }
            if a.element.compatible != b.element.compatible { return a.element.compatible }
            return a.offset < b.offset
        }.map(\.element)
        if let limit, let fit = ranked.first(where: { source in
            source.height.map { $0 <= limit } ?? labelledHigh(source.label)
        }) { return fit }
        return ranked.first
    }

    private static func labelledHigh(_ label: String?) -> Bool {
        label?.range(of: #"^\s*(hq|high|hd|high quality)\s*$"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    private static func labelledLow(_ label: String?) -> Bool {
        label?.range(of: #"^\s*(lq|low|sd|low quality)\s*$"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// Every URL `pattern` captures; when there are several and each names its height, the one
    /// that best fits the quality setting, otherwise the first.
    static func choosePatternMatch(_ pattern: String, in html: String, base: URL, quality: QualityPreset) -> RecipeSource? {
        var seen = Set<String>()
        let found = matches(pattern, in: html, group: 1).compactMap { resolve($0, base: base) }
            .filter { seen.insert($0.absoluteString).inserted }
            .map { RecipeSource(url: $0, height: height(in: $0)) }
        guard found.count > 1, found.allSatisfy({ $0.height != nil }) else { return found.first }
        return choose(found, quality: quality)
    }

    /// "720" for ".../92390_720p.mp4/", nil for ".../606293.mp4" (an id, not a height).
    static func height(in url: URL) -> Int? {
        firstMatch(#"(?<!\d)(\d{3,4})p?\.(?:mp4|webm|m3u8)"#, in: url.path).flatMap(Int.init)
            .flatMap { (144...4320).contains($0) ? $0 : nil }
    }

    private static func isCompatible(_ text: String) -> Bool {
        text.range(of: #"av01|\bav1\b|hvc1|hev1|hevc"#, options: [.regularExpression, .caseInsensitive]) == nil
    }

    static func linkURL(_ link: Recipe.Link, page: URL, html: String) -> URL? {
        var url = link.url
        if let find = link.find {
            guard let value = firstMatch(find, in: page.absoluteString) ?? firstMatch(find, in: html) else { return nil }
            url = url.replacingOccurrences(of: "$1", with: value)
        }
        return resolve(url, base: page)
    }

    static func unescape(_ html: String) -> String {
        html.replacingOccurrences(of: #"\""#, with: "\"")
            .replacingOccurrences(of: #"\'"#, with: "'")
            .replacingOccurrences(of: #"\/"#, with: "/")
            .replacingOccurrences(of: #"\u0026"#, with: "&")
            .replacingOccurrences(of: #"\u003c"#, with: "<")
            .replacingOccurrences(of: #"\u003e"#, with: ">")
    }

    /// The last path component without its extension: "128512-wide_and_wet" for ".../128512-wide_and_wet.html".
    static func pageID(_ page: URL) -> String? {
        let name = page.deletingPathExtension().lastPathComponent
        return name.isEmpty || name == "/" ? nil : name
    }

    static func defaultTitle(in html: String) -> String? {
        (firstMatch(#"<meta[^>]+property=["']og:title["'][^>]+content=["']([^"']+)"#, in: html)
            ?? firstMatch(#"<title[^>]*>([^<]+)</title>"#, in: html)).map(cleanTitle)
    }

    static func cleanTitle(_ raw: String) -> String {
        raw.replacingOccurrences(of: "&amp;", with: "&").replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func regexReplacement(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\")
    }

    static func firstMatch(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges > 1, let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }

    static func matches(_ pattern: String, in text: String, group: Int) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
            guard match.numberOfRanges > group, let range = Range(match.range(at: group), in: text) else { return nil }
            return String(text[range])
        }
    }

    private static func tags(_ name: String, in html: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: "<\(name)\\b[^>]*>", options: [.caseInsensitive]) else { return [] }
        let text = html as NSString
        return regex.matches(in: html, range: NSRange(location: 0, length: text.length)).map { text.substring(with: $0.range) }
    }

    private static func attribute(_ name: String, in tag: String) -> String? {
        firstMatch(#"\b\#(name)\s*=\s*"([^"]*)""#, in: tag) ?? firstMatch(#"\b\#(name)\s*=\s*'([^']*)'"#, in: tag)
    }

    private static func resolve(_ src: String, base: URL) -> URL? {
        let cleaned = src.replacingOccurrences(of: "&amp;", with: "&").trimmingCharacters(in: .whitespaces)
        guard !cleaned.isEmpty, let url = URL(string: cleaned, relativeTo: base)?.absoluteURL,
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return nil }
        return url
    }

    private static let pageAccept = "text/html,application/xhtml+xml"
    /// For `link` URLs, which are often player APIs that answer only requests that accept JSON.
    private static let dataAccept = "application/json, text/html;q=0.9, */*;q=0.8"

    private static func fetch(_ url: URL, referer: String?, mode: Recipe.Fetch, accept: String = pageAccept) async throws -> String {
        if mode == .browser { return try await BrowserFetch.page(url, referer: referer) }
        do {
            let html = try await plainFetch(url, referer: referer, accept: accept)
            if BrowserFetch.isChallenge(html) { return try await BrowserFetch.page(url, referer: referer) }
            return html
        } catch RecipeError.pageUnavailable(let detail) where detail == "HTTP 403" || detail == "HTTP 503" {
            return try await BrowserFetch.page(url, referer: referer)
        }
    }

    private static func plainFetch(_ url: URL, referer: String?, accept: String) async throws -> String {
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue(EmbedFinder.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(accept, forHTTPHeaderField: "Accept")
        if let referer { request.setValue(referer, forHTTPHeaderField: "Referer") }
        let data: Data, response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw RecipeError.pageUnavailable(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw RecipeError.pageUnavailable("HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)")
        }
        return String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
    }
}
