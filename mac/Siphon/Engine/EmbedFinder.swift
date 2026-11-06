import Foundation

/// Finds the video player a page embeds from another host in an iframe, for sites whose
/// pages have no video of their own. Reads HTML only; nothing from the page is run.
enum EmbedFinder {
    static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/136.0 Safari/537.36"

    /// Frames that are never the video: ads, social widgets, captchas, analytics.
    static let ignoredHostFragments = [
        "doubleclick", "googlesyndication", "googletagmanager", "google-analytics", "recaptcha", "hcaptcha",
        "challenges.cloudflare", "facebook.com", "twitter.com", "disqus", "addthis",
        "sharethis", "exoclick", "exosrv", "juicyads", "trafficjunky", "trafficstars", "adsterra", "popads",
        "adserver", "adnxs", "taboola", "outbrain", "chatwoot", "intercom",
    ]

    static func fetchEmbed(for page: URL) async -> URL? {
        var request = URLRequest(url: page, timeoutInterval: 20)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return nil }
        let html = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
        return find(in: html, pageURL: http.url ?? page)
    }

    /// The most player-like iframe: an embed/player URL, inside a player or video container,
    /// or allowed to go fullscreen. Nil when no frame looks like a player.
    static func find(in html: String, pageURL: URL) -> URL? {
        let pattern = #"<iframe\b[^>]*>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let text = html as NSString
        var best: (url: URL, score: Int)?
        for match in regex.matches(in: html, range: NSRange(location: 0, length: text.length)) {
            let tag = text.substring(with: match.range)
            guard let src = attribute("src", in: tag) ?? attribute("data-src", in: tag),
                  let url = URL(string: src.replacingOccurrences(of: "&amp;", with: "&"), relativeTo: pageURL)?.absoluteURL,
                  let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
                  url.host != nil else { continue }
            let lowered = url.absoluteString.lowercased()
            let host = url.host?.lowercased() ?? ""
            if ignoredHostFragments.contains(where: lowered.contains) || host == "x.com" || host.hasSuffix(".x.com") { continue }

            var score = 0
            let path = url.path.lowercased()
            if path.contains("embed") || path.hasPrefix("/e/") || path.contains("player") { score += 3 }
            if tag.lowercased().contains("allowfullscreen") { score += 1 }
            let before = text.substring(with: NSRange(location: max(0, match.range.location - 400),
                                                      length: min(400, match.range.location))).lowercased()
            if before.range(of: #"(class|id)="[^"]*(player|video)[^"]*""#, options: .regularExpression) != nil { score += 2 }
            if score >= 2, score > (best?.score ?? 0) { best = (url, score) }
        }
        return best?.url
    }

    private static func attribute(_ name: String, in tag: String) -> String? {
        let pattern = #"\b\#(name)\s*=\s*("([^"]*)"|'([^']*)')"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: tag, range: NSRange(tag.startIndex..., in: tag)) else { return nil }
        for group in [2, 3] {
            if let range = Range(match.range(at: group), in: tag) {
                let value = String(tag[range]).trimmingCharacters(in: .whitespaces)
                return value.isEmpty ? nil : value
            }
        }
        return nil
    }
}
