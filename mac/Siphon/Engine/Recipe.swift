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

    /// The recipe's steps in plain words, for the Sites window.
    var summary: String {
        var steps: [String] = []
        if let base, let builtIn = Self.builtIn(named: base) {
            steps.append("built-in \"\(builtIn.displayName)\":")
        }
        if fetch == .browser { steps.append("fetch pages as desktop Chrome (through yt-dlp)") }
        if let embed {
            steps.append(embed.match.map { "open the player iframe matching \($0)" } ?? "open the most player-like iframe")
            if media == .sources { steps.append(embed.referer == false ? "fetch it without a referer" : "fetch it with the page as referer") }
        }
        if unescape == true { steps.append("undo JavaScript escaping") }
        switch media {
        case .ytdlp: steps.append(embed == nil ? "give yt-dlp the page" : "give yt-dlp the player's URL")
        case .sources: steps.append("pick the best video source for the Quality setting")
        case .pattern:
            if let pattern { steps.append("give yt-dlp the URL matching \(pattern)") }
            if let patterns { steps.append("give yt-dlp the first URL found under \(patterns.count) common player-config keys") }
        }
        if let title { steps.append("title from \(title)") }
        let text = steps.joined(separator: ", ").replacingOccurrences(of: ":,", with: ":") + "."
        return text.prefix(1).uppercased() + text.dropFirst()
    }

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
            #"["']?(?:file|video_url|videoUrl|video_src|videoSrc|contentUrl|mp4|mp4Url|src|source|url)["']?\s*:\s*["'](https?://[^"'\s]+\.(?:m3u8|mpd|mp4|webm)(?:\?[^"'\s]*)?)["']"#,
        ])

    static let builtIns = [followEmbed, smartScan, playerConfig]

    static func builtIn(named name: String) -> Recipe? {
        builtIns.first { $0.base == name }
    }

    var displayName: String {
        switch base {
        case "followEmbed": "follow the embedded player"
        case "smartScan": "read the player's video sources"
        case "playerConfig": "find the video in the player configuration"
        default: base ?? "custom"
        }
    }

    // MARK: - Coding

    private enum CodingKeys: String, CodingKey {
        case base, fetch, embed, unescape, media, pattern, patterns, title, mediaReferer
    }

    init(base: String? = nil, fetch: Fetch? = nil, embed: Embed? = nil, unescape: Bool? = nil, media: Media,
         pattern: String? = nil, patterns: [String]? = nil, title: String? = nil, mediaReferer: Bool? = nil) {
        self.base = base
        self.fetch = fetch
        self.embed = embed
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
}

struct RecipeSource: Equatable {
    var url: URL
    var label: String?
    var height: Int?
}

enum RecipeError: LocalizedError, Equatable {
    case pageUnavailable(String)
    case noEmbed
    case noSources

    var errorDescription: String? {
        switch self {
        case .pageUnavailable(let detail): "Couldn't load the page: \(detail)"
        case .noEmbed: "No embedded player found on the page"
        case .noSources: "No video sources found in the player"
        }
    }
}

enum RecipeRunner {
    static func resolve(page: URL, recipe: Recipe, quality: QualityPreset) async throws -> RecipeResolution {
        let mode = recipe.fetch ?? .auto
        let pageHTML = try await fetch(page, referer: nil, mode: mode)
        let title = recipe.title.flatMap { firstMatch($0, in: pageHTML) }.map(cleanTitle)
            ?? (recipe.media == .ytdlp ? nil : defaultTitle(in: pageHTML))
        let videoID = pageID(page)

        var html = pageHTML
        var base = page
        var embedURL: URL?
        if let embed = recipe.embed {
            let found = embed.match.map { iframe(matching: $0, in: pageHTML, base: page) }
                ?? EmbedFinder.find(in: pageHTML, pageURL: page)
            guard let found else { throw RecipeError.noEmbed }
            embedURL = found
            if recipe.media != .ytdlp {
                html = try await fetch(found, referer: embed.referer == false ? nil : page.absoluteString, mode: mode)
                base = found
            }
        }
        if recipe.unescape == true { html = unescape(html) }

        switch recipe.media {
        case .ytdlp:
            guard let embedURL else { throw RecipeError.noEmbed }
            return RecipeResolution(url: embedURL, referer: page.absoluteString, title: title, videoID: nil, embedURL: embedURL)
        case .sources:
            guard let source = choose(sources(in: html, base: base), quality: quality) else { throw RecipeError.noSources }
            return RecipeResolution(
                url: source.url, referer: recipe.mediaReferer == true ? base.absoluteString : nil,
                title: title, videoID: videoID, sourceLabel: source.label, embedURL: embedURL)
        case .pattern:
            let candidates = (recipe.pattern.map { [$0] } ?? []) + (recipe.patterns ?? [])
            guard let url = candidates.lazy.compactMap({ firstMatch($0, in: html).flatMap { resolve($0, base: base) } }).first
            else { throw RecipeError.noSources }
            return RecipeResolution(
                url: url, referer: recipe.mediaReferer == true ? base.absoluteString : nil,
                title: title, videoID: videoID, embedURL: embedURL)
        }
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

    /// <source> tags plus any <video src=...>, deduplicated, with the height read from the label or URL.
    static func sources(in html: String, base: URL) -> [RecipeSource] {
        var seen = Set<String>()
        var result: [RecipeSource] = []
        for tag in tags("source", in: html) + tags("video", in: html) {
            guard let src = attribute("src", in: tag), let url = resolve(src, base: base),
                  seen.insert(url.absoluteString).inserted else { continue }
            let label = attribute("title", in: tag) ?? attribute("label", in: tag) ?? attribute("res", in: tag)
                ?? attribute("size", in: tag) ?? attribute("data-quality", in: tag)
            let height = (label.flatMap { firstMatch(#"(\d{3,4})"#, in: $0) }
                ?? firstMatch(#"(\d{3,4})p?\.(?:mp4|webm|m3u8)"#, in: url.path)).flatMap { Int($0) }
            result.append(RecipeSource(url: url, label: label, height: height))
        }
        return result
    }

    /// The tallest source within the quality setting's limit; the tallest overall if none fit.
    static func choose(_ sources: [RecipeSource], quality: QualityPreset) -> RecipeSource? {
        let limit: Int? = switch quality {
        case .p2160: 2160
        case .p1440: 1440
        case .p1080: 1080
        case .p720: 720
        case .configFile, .best, .audioOnly: nil
        }
        let ranked = sources.sorted { ($0.height ?? 0) > ($1.height ?? 0) }
        if let limit, let fit = ranked.first(where: { ($0.height ?? 0) <= limit && $0.height != nil }) { return fit }
        return ranked.first
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

    private static func fetch(_ url: URL, referer: String?, mode: Recipe.Fetch) async throws -> String {
        if mode == .browser { return try await BrowserFetch.page(url, referer: referer) }
        do {
            let html = try await plainFetch(url, referer: referer)
            if BrowserFetch.isChallenge(html) { return try await BrowserFetch.page(url, referer: referer) }
            return html
        } catch RecipeError.pageUnavailable(let detail) where detail == "HTTP 403" || detail == "HTTP 503" {
            return try await BrowserFetch.page(url, referer: referer)
        }
    }

    private static func plainFetch(_ url: URL, referer: String?) async throws -> String {
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue(EmbedFinder.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
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
