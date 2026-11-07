import Foundation

/// Decides when Siphon tests a site it has no working entry for, which automatic fixes to
/// try, and what to record in the persistent `sites.json`.
enum SiteLearner {
    struct Attempt: Equatable {
        let label: String
        /// nil gives yt-dlp the page as it is.
        var recipe: Recipe?
    }

    static let impersonate = Recipe(download: .init(impersonate: true))
    static let impersonateWithReferer = Recipe(download: .init(impersonate: true, siteReferer: true))
    static let scanPage = Recipe(download: .init(impersonate: true, scanPage: true))

    enum FailureKind: Equatable {
        /// Offline, timeouts, full disk: says nothing about the site.
        case local
        /// One video is gone, private, or needs an account: says nothing about the site as a whole.
        case itemSpecific
        case drm
        /// yt-dlp refuses the site as primarily used for piracy.
        case piracy
        /// Worth trying the next fix.
        case site
    }

    /// Every download from a site is also a test of its entry, which is replaced when another fix
    /// works better, unless the site is unsupported or its recipe has hand-written steps the
    /// learner couldn't find again (those are reported, never overwritten).
    static func shouldLearn(_ site: SiteConfig?) -> Bool {
        guard let site else { return true }
        guard site.status != "unsupported" else { return false }
        return site.isLearned || site.recipe.map(isStandard) ?? true
    }

    /// A recipe one of the learner's own fixes produces.
    static func isStandard(_ recipe: Recipe) -> Bool {
        plainAttempts.contains { $0.recipe == recipe }
    }

    /// Lowercased host without a leading "www." or "m.".
    static func domain(for url: String) -> String? {
        guard var host = URL(string: url)?.host?.lowercased() else { return nil }
        for prefix in ["www.", "m."] where host.hasPrefix(prefix) && host.count > prefix.count + 3 {
            host.removeFirst(prefix.count)
        }
        return host
    }

    /// The automatic fixes, plain yt-dlp first.
    static let plainAttempts = [
        Attempt(label: "yt-dlp's built-in support"),
        Attempt(label: "browser impersonation", recipe: impersonate),
        Attempt(label: "browser impersonation with the site as referer", recipe: impersonateWithReferer),
        Attempt(label: "scanning the page for media", recipe: scanPage),
        Attempt(label: "following the page's embedded player", recipe: .followEmbed),
        Attempt(label: "giving yt-dlp the embedded player's own video page", recipe: .embedPage),
        Attempt(label: "reading video sources from the embedded player", recipe: .smartScan),
        Attempt(label: "finding the video in the page's player configuration", recipe: .playerConfig),
        Attempt(label: "reading video sources from the page", recipe: .pageSources),
        Attempt(label: "asking the site's player data address", recipe: .playerAPI),
    ]

    /// The saved recipe first, then the automatic fixes in order.
    static func attempts(for url: String, existing: SiteConfig?) -> [Attempt] {
        var list: [Attempt] = []
        if let recipe = existing?.recipe { list.append(Attempt(label: "the saved recipe", recipe: recipe)) }
        list += plainAttempts
        var kept: [Attempt] = []
        for attempt in list where !kept.contains(where: { $0.recipe == attempt.recipe }) {
            kept.append(attempt)
        }
        return kept
    }

    static func classify(_ reason: String) -> FailureKind {
        let text = reason.lowercased()
        let local = [
            "nodename nor servname", "network is unreachable", "timed out", "no route to host",
            "temporary failure in name resolution", "appears to be offline", "errno 8]", "errno 51]", "errno 65]",
            "no space left", "read-only file system", "yt-dlp not found", "could not start yt-dlp",
        ]
        if local.contains(where: text.contains) { return .local }
        if text.contains("used for piracy") || text.contains("[piracy]") { return .piracy }
        if text.contains("drm") { return .drm }
        let item = [
            "http error 404", "http error 410", "video unavailable", "private video", "has been removed",
            "no longer available", "sign in", "log in", "login", "logged-in", "members-only", "age-restricted",
            "--cookies",
        ]
        if item.contains(where: text.contains) { return .itemSpecific }
        return .site
    }

    static func today(_ date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    static func workingEntry(url: String, attempt: Attempt, extractor: String?, firstFailure: String?,
                             testResult: String, existing: SiteConfig?, embedURL: URL? = nil,
                             observed: RecipeObservation? = nil, date: Date = Date()) -> SiteConfig? {
        guard let domain = domain(for: url) else { return nil }
        let handler = extractor.map { "yt-dlp's \($0) extractor" } ?? "yt-dlp"
        let recipe = attempt.recipe.map { specialized($0, with: observed ?? RecipeObservation()) }
        let builtIn = attempt.recipe?.base
        var notes: String
        if let existing, existing.status == "working", existing.recipe == recipe, let kept = existing.notes {
            notes = kept
        } else if builtIn == "embedPage" {
            let before = firstFailure.map { "The plain download failed (\($0)). " } ?? ""
            let host = embedURL?.host.map { " from \($0)" } ?? ""
            notes = "Learned by Siphon: \(before)The page embeds a player\(host) whose address yt-dlp doesn't recognise, but it recognises the player's own video page. Siphon finds the player on each page and gives \(handler) that video page."
        } else if builtIn == "playerAPI" {
            let before = firstFailure.map { "The plain download failed (\($0)). " } ?? ""
            notes = "Learned by Siphon: \(before)Neither the page nor a player on it lists the video; the player asks the site's player data address for it. Siphon asks that address too, picks the file that fits the Quality setting, and gives yt-dlp that file."
        } else if builtIn == "playerConfig" {
            let before = firstFailure.map { "The plain download failed (\($0)). " } ?? ""
            notes = "Learned by Siphon: \(before)The video's address is in the page's player configuration (a script), which yt-dlp doesn't read. Siphon finds it under a common player key and gives yt-dlp that stream or file."
        } else if builtIn == "pageSources" {
            let before = firstFailure.map { "The plain download failed (\($0)). " } ?? ""
            notes = "Learned by Siphon: \(before)The page lists its video sources itself, in a form yt-dlp doesn't read. Siphon reads them, picks the quality that fits the Quality setting, and gives yt-dlp that file."
        } else if builtIn == "smartScan" {
            let before = firstFailure.map { "The plain download failed (\($0)). " } ?? ""
            let host = embedURL?.host.map { " from \($0)" } ?? ""
            notes = "Learned by Siphon: \(before)The page embeds a player\(host) that yt-dlp can't read directly. Siphon reads the player's video sources itself (undoing JavaScript escaping), picks the quality that fits the Quality setting, and gives yt-dlp that file."
        } else if builtIn == "followEmbed" {
            let before = firstFailure.map { "The plain download failed (\($0)). " } ?? ""
            let host = embedURL?.host.map { " from \($0)" } ?? ""
            notes = "Learned by Siphon: \(before)The page has no video of its own; it embeds a player\(host) in an iframe, which yt-dlp doesn't follow. Siphon finds that iframe on each page and passes the player's URL to \(handler), with the page as referer."
        } else if attempt.recipe == nil {
            notes = "Learned by Siphon on first download: \(handler) handled it with no extra options."
        } else {
            let before = firstFailure.map { "The plain download failed (\($0)). " } ?? ""
            notes = "Learned by Siphon: \(before)Retrying with \(attempt.label) worked, so the site's recipe now downloads that way."
        }
        if let recipe, let attempted = attempt.recipe, recipe != attempted, !notes.contains("Remembered from the download:") {
            notes += " Remembered from the download: " + remembered(from: attempted, to: recipe) + "."
        }
        return SiteConfig(
            id: existing?.id ?? id(for: domain), name: existing?.name ?? domain, match: existing?.match ?? [domain],
            method: recipe != nil ? "recipe" : "builtin",
            status: "working",
            exampleUrl: existing?.exampleUrl ?? url,
            lastTested: today(date), testResult: testResult, notes: notes, source: "learned",
            recipe: recipe
        )
    }

    /// Fills in what a successful download showed about the site, so the next download goes
    /// straight to it: the player host picked by scoring, the player key that held the URL, and
    /// a title trim checked on the page. Only empty fields are filled; nothing is guessed.
    static func specialized(_ recipe: Recipe, with observed: RecipeObservation) -> Recipe {
        var result = recipe
        if result.embed != nil, result.embed?.match == nil, let host = observed.embedHost {
            result.embed?.match = NSRegularExpression.escapedPattern(for: host) + "/"
        }
        if result.media == .pattern, result.pattern == nil, let pattern = observed.matchedPattern {
            result.pattern = pattern
        }
        if result.title == nil, let title = observed.titlePattern {
            result.title = title
        }
        return result
    }

    struct SharedPlayer: Equatable, Identifiable {
        var host: String
        var siteNames: [String]
        var id: String { host }
    }

    /// Player hosts that two or more working sites embed. Each is a candidate for its own built-in,
    /// which a person still writes and checks; Siphon only points it out.
    static func sharedPlayers(in sites: [SiteConfig]) -> [SharedPlayer] {
        var byHost: [String: [String]] = [:]
        for site in sites where site.status == "working" {
            guard let match = site.recipe?.embed?.match else { continue }
            let host = match.replacingOccurrences(of: "\\", with: "")
                .split(separator: "/").first.map(String.init)?.lowercased() ?? match
            byHost[host, default: []].append(site.name)
        }
        return byHost.filter { $0.value.count >= 2 }
            .map { SharedPlayer(host: $0.key, siteNames: $0.value.sorted { $0.localizedStandardCompare($1) == .orderedAscending }) }
            .sorted { $0.host < $1.host }
    }

    private static func remembered(from attempted: Recipe, to recipe: Recipe) -> String {
        var parts: [String] = []
        if recipe.embed?.match != attempted.embed?.match, let match = recipe.embed?.match {
            parts.append("the player iframe (\(match.replacingOccurrences(of: "\\", with: "")))")
        }
        if recipe.pattern != attempted.pattern { parts.append("the player-config key that held the video") }
        if recipe.title != attempted.title { parts.append("how to remove the site's name from titles") }
        return parts.joined(separator: ", ")
    }

    static func failedEntry(url: String, kind: FailureKind, tried: [Attempt], firstFailure: String?,
                            lastFailure: String, existing: SiteConfig?, date: Date = Date()) -> SiteConfig? {
        guard let domain = domain(for: url) else { return nil }
        let refused = kind == .drm || kind == .piracy
        let notes = kind == .piracy
            ? "yt-dlp no longer supports this site because it has been determined to be primarily used for piracy. Siphon doesn't work around that."
            : refused
            ? "The site's media is DRM-protected. Siphon doesn't circumvent DRM."
            : "Learned by Siphon: \(tried.map(\.label).joined(separator: ", ")) all failed. "
                + (firstFailure.map { "First error: \($0). " } ?? "")
                + "Needs a closer look: a new built-in recipe, the user's browser session, or a plugin."
        return SiteConfig(
            id: existing?.id ?? id(for: domain), name: existing?.name ?? domain, match: existing?.match ?? [domain],
            method: refused ? "unsupported" : "builtin", status: refused ? "unsupported" : "broken",
            exampleUrl: existing?.exampleUrl ?? url,
            lastTested: today(date), testResult: "Failed: \(lastFailure)", notes: notes, source: "learned"
        )
    }

    private static func id(for domain: String) -> String {
        domain.replacingOccurrences(of: ".", with: "-")
    }
}
