import Foundation

/// Decides when Siphon tests a site it has no working entry for, which automatic fixes to
/// try, and what to record in the persistent `sites.json`.
enum SiteLearner {
    struct Attempt: Equatable {
        let label: String
        let arguments: [String]
        /// Run a recipe to find the URL for yt-dlp instead of giving it the page.
        var recipe: Recipe?

        var followEmbed: Bool { recipe == .followEmbed }
    }

    enum FailureKind: Equatable {
        /// Offline, timeouts, full disk: says nothing about the site.
        case local
        /// One video is gone, private, or needs an account: says nothing about the site as a whole.
        case itemSpecific
        case drm
        /// Worth trying the next fix.
        case site
    }

    /// Sites with no entry are tested, and so are entries Siphon learned itself
    /// (to refresh them or to try again after a failure). Curated entries are left alone.
    static func shouldLearn(_ site: SiteConfig?) -> Bool {
        guard let site else { return true }
        return site.isLearned && site.status != "unsupported"
    }

    /// Lowercased host without a leading "www." or "m.".
    static func domain(for url: String) -> String? {
        guard var host = URL(string: url)?.host?.lowercased() else { return nil }
        for prefix in ["www.", "m."] where host.hasPrefix(prefix) && host.count > prefix.count + 3 {
            host.removeFirst(prefix.count)
        }
        return host
    }

    /// Plain yt-dlp first (or the learned entry's options), then the automatic fixes in order.
    static func attempts(for url: String, existing: SiteConfig?) -> [Attempt] {
        let origin = URL(string: url).flatMap { u in u.scheme.flatMap { s in u.host.map { "\(s)://\($0)" } } } ?? ""
        var list: [Attempt] = []
        if let existing, let recipe = existing.recipe {
            list.append(Attempt(label: "the saved recipe", arguments: existing.ytDlpArgs, recipe: recipe))
        } else if let existing, !existing.ytDlpArgs.isEmpty {
            list.append(Attempt(label: "saved options", arguments: existing.ytDlpArgs))
        }
        list += [
            Attempt(label: "yt-dlp's built-in support", arguments: []),
            Attempt(label: "browser impersonation", arguments: ["--impersonate", "chrome"]),
            Attempt(label: "browser impersonation with the site as referer",
                    arguments: ["--impersonate", "chrome", "--add-headers", "Referer:\(origin)/"]),
            Attempt(label: "scanning the page for media", arguments: ["--use-extractors", "generic", "--impersonate", "chrome"]),
            Attempt(label: "following the page's embedded player", arguments: [], recipe: .followEmbed),
            Attempt(label: "reading video sources from the embedded player", arguments: [], recipe: .smartScan),
        ]
        var kept: [Attempt] = []
        for attempt in list where !kept.contains(where: { $0.recipe == attempt.recipe && $0.arguments == attempt.arguments }) {
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
                             date: Date = Date()) -> SiteConfig? {
        guard let domain = domain(for: url) else { return nil }
        let handler = extractor.map { "yt-dlp's \($0) extractor" } ?? "yt-dlp"
        let notes: String
        if let existing, existing.status == "working", existing.ytDlpArgs == attempt.arguments,
           existing.recipe == attempt.recipe, let kept = existing.notes {
            notes = kept
        } else if attempt.recipe == .smartScan {
            let before = firstFailure.map { "The plain download failed (\($0)). " } ?? ""
            let host = embedURL?.host.map { " from \($0)" } ?? ""
            notes = "Learned by Siphon: \(before)The page embeds a player\(host) that yt-dlp can't read directly. Siphon reads the player's video sources itself (undoing JavaScript escaping), picks the quality that fits the Quality setting, and gives yt-dlp that file."
        } else if attempt.followEmbed {
            let before = firstFailure.map { "The plain download failed (\($0)). " } ?? ""
            let host = embedURL?.host.map { " from \($0)" } ?? ""
            notes = "Learned by Siphon: \(before)The page has no video of its own; it embeds a player\(host) in an iframe, which yt-dlp doesn't follow. Siphon finds that iframe on each page and passes the player's URL to \(handler), with the page as referer."
        } else if attempt.arguments.isEmpty {
            notes = "Learned by Siphon on first download: \(handler) handled it with no extra options."
        } else {
            let before = firstFailure.map { "The plain download failed (\($0)). " } ?? ""
            notes = "Learned by Siphon: \(before)Retrying with \(attempt.label) (\(attempt.arguments.joined(separator: " "))) worked, so those options are now used for this site."
        }
        return SiteConfig(
            id: existing?.id ?? id(for: domain), name: existing?.name ?? domain, match: existing?.match ?? [domain],
            method: attempt.recipe != nil ? "recipe" : attempt.arguments.isEmpty ? "builtin" : "options",
            status: "working",
            ytDlpArgs: attempt.arguments, exampleUrl: existing?.exampleUrl ?? url,
            lastTested: today(date), testResult: testResult, notes: notes, source: "learned",
            recipe: attempt.recipe
        )
    }

    static func failedEntry(url: String, kind: FailureKind, tried: [Attempt], firstFailure: String?,
                            lastFailure: String, existing: SiteConfig?, date: Date = Date()) -> SiteConfig? {
        guard let domain = domain(for: url) else { return nil }
        let drm = kind == .drm
        let notes = drm
            ? "The site's media is DRM-protected. Siphon doesn't circumvent DRM."
            : "Learned by Siphon: \(tried.map(\.label).joined(separator: ", ")) all failed. "
                + (firstFailure.map { "First error: \($0). " } ?? "")
                + "Needs a closer look: per-site options, browser cookies, or a plugin."
        return SiteConfig(
            id: existing?.id ?? id(for: domain), name: existing?.name ?? domain, match: existing?.match ?? [domain],
            method: drm ? "unsupported" : "builtin", status: drm ? "unsupported" : "broken",
            ytDlpArgs: [], exampleUrl: existing?.exampleUrl ?? url,
            lastTested: today(date), testResult: "Failed: \(lastFailure)", notes: notes, source: "learned"
        )
    }

    private static func id(for domain: String) -> String {
        domain.replacingOccurrences(of: ".", with: "-")
    }
}
