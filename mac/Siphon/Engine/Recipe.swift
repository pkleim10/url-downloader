import Foundation

/// A declarative way to find a site's video that Siphon carries out itself in Swift.
/// A recipe can only fetch pages and read their text; nothing from a site is ever run.
///
///     "recipe": {
///       "embed": { "match": "mydaddy\\.cc/video/", "referer": true },
///       "unescape": true,
///       "media": "sources",
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
    }

    /// Follow the page's player iframe first.
    var embed: Embed?
    /// Undo JavaScript string escaping (\" \/ \u0026) before reading the markup.
    var unescape: Bool?
    var media: Media
    /// Regex with one capture group, applied to the page, for the title.
    var title: String?
    /// Send the page that listed the media as referer when downloading it.
    var mediaReferer: Bool?

    /// The recipe's steps in plain words, for the Sites window.
    var summary: String {
        var steps: [String] = []
        if let embed {
            steps.append(embed.match.map { "Open the player iframe matching \($0)" } ?? "Open the most player-like iframe")
            if media == .sources { steps.append(embed.referer == false ? "fetch it without a referer" : "fetch it with the page as referer") }
        }
        if unescape == true { steps.append("undo JavaScript escaping") }
        switch media {
        case .ytdlp: steps.append(embed == nil ? "give yt-dlp the page" : "give yt-dlp the player's URL")
        case .sources: steps.append("pick the best video source for the Quality setting")
        }
        if let title { steps.append("title from \(title)") }
        return steps.joined(separator: ", ") + "."
    }

    /// Download the page's player iframe with yt-dlp (the "embed" automatic fix).
    static let followEmbed = Recipe(embed: Embed(), media: .ytdlp)
    /// Read video sources straight out of the page's player iframe (the "smart scan" fix).
    static let smartScan = Recipe(embed: Embed(), unescape: true, media: .sources)
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
        let pageHTML = try await fetch(page, referer: nil)
        let title = recipe.title.flatMap { firstMatch($0, in: pageHTML) }.map(cleanTitle)
            ?? (recipe.media == .sources ? defaultTitle(in: pageHTML) : nil)
        let videoID = pageID(page)

        var html = pageHTML
        var base = page
        var embedURL: URL?
        if let embed = recipe.embed {
            let found = embed.match.map { iframe(matching: $0, in: pageHTML, base: page) }
                ?? EmbedFinder.find(in: pageHTML, pageURL: page)
            guard let found else { throw RecipeError.noEmbed }
            embedURL = found
            if recipe.media == .sources {
                html = try await fetch(found, referer: embed.referer == false ? nil : page.absoluteString)
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

    private static func fetch(_ url: URL, referer: String?) async throws -> String {
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
