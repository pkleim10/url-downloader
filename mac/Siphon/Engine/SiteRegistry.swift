import Foundation

/// One entry in `sites/sites.json`. The same file drives the web version's Sites panel.
struct SiteConfig: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var match: [String]
    var method: String
    var status: String
    var ytDlpArgs: [String]
    var plugin: String?
    var exampleUrl: String?
    var lastTested: String?
    var testResult: String?
    var notes: String?
    /// "learned" for entries Siphon recorded itself; nil for entries shipped in the repo.
    var source: String?
    /// How Siphon finds the video itself before handing a URL to yt-dlp (see `Recipe`).
    var recipe: Recipe?

    enum CodingKeys: String, CodingKey {
        case id, name, match, method, status, ytDlpArgs, plugin, exampleUrl, lastTested, testResult, notes, source
        case recipe
    }

    /// Read from older files only: `"method": "embed"` with `"followEmbed": true` is the follow-embed recipe.
    private enum LegacyKeys: String, CodingKey { case followEmbed }

    init(id: String, name: String, match: [String], method: String, status: String,
         ytDlpArgs: [String] = [], plugin: String? = nil, exampleUrl: String? = nil,
         lastTested: String? = nil, testResult: String? = nil, notes: String? = nil, source: String? = nil,
         recipe: Recipe? = nil) {
        self.recipe = recipe
        self.id = id
        self.name = name
        self.match = match
        self.method = method
        self.status = status
        self.ytDlpArgs = ytDlpArgs
        self.plugin = plugin
        self.exampleUrl = exampleUrl
        self.lastTested = lastTested
        self.testResult = testResult
        self.notes = notes
        self.source = source
    }

    var isLearned: Bool { source == "learned" }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? id
        match = try c.decodeIfPresent([String].self, forKey: .match) ?? []
        method = try c.decodeIfPresent(String.self, forKey: .method) ?? "builtin"
        status = try c.decodeIfPresent(String.self, forKey: .status) ?? "untested"
        ytDlpArgs = try c.decodeIfPresent([String].self, forKey: .ytDlpArgs) ?? []
        plugin = try c.decodeIfPresent(String.self, forKey: .plugin)
        exampleUrl = try c.decodeIfPresent(String.self, forKey: .exampleUrl)
        lastTested = try c.decodeIfPresent(String.self, forKey: .lastTested)
        testResult = try c.decodeIfPresent(String.self, forKey: .testResult)
        notes = try c.decodeIfPresent(String.self, forKey: .notes)
        source = try c.decodeIfPresent(String.self, forKey: .source)
        recipe = try? c.decodeIfPresent(Recipe.self, forKey: .recipe)
        let legacy = try decoder.container(keyedBy: LegacyKeys.self)
        if recipe == nil, (try? legacy.decodeIfPresent(Bool.self, forKey: .followEmbed)) == true {
            recipe = .followEmbed
        }
        if method == "embed" { method = "recipe" }
    }

    func overlaps(_ other: SiteConfig) -> Bool {
        id == other.id || match.contains { other.matches(host: $0) } || other.match.contains { matches(host: $0) }
    }

    /// True when `host` is one of the `match` domains or a subdomain of one.
    func matches(host: String) -> Bool {
        let host = host.lowercased()
        return match.contains { pattern in
            let domain = pattern.lowercased()
            return host == domain || host.hasSuffix("." + domain)
        }
    }
}

struct SiteRegistry {
    var sites: [SiteConfig]
    /// Passed to yt-dlp with `--plugin-dirs` when it exists.
    var pluginDirectory: URL?

    static let empty = SiteRegistry(sites: [], pluginDirectory: nil)

    /// Loads `sites.json` and `plugins/` from a sites folder (the bundled copy by default).
    static func load(from folder: URL?) -> SiteRegistry {
        guard let folder else { return .empty }
        let file = folder.appendingPathComponent("sites.json")
        let plugins = folder.appendingPathComponent("plugins", isDirectory: true)
        let pluginDirectory = FileManager.default.fileExists(atPath: plugins.path) ? plugins : nil
        guard let data = try? Data(contentsOf: file) else {
            return SiteRegistry(sites: [], pluginDirectory: pluginDirectory)
        }
        return SiteRegistry(sites: decode(data), pluginDirectory: pluginDirectory)
    }

    static func decode(_ data: Data) -> [SiteConfig] {
        struct File: Decodable { var sites: [SiteConfig]? }
        return (try? JSONDecoder().decode(File.self, from: data))?.sites ?? []
    }

    static var bundledFolder: URL? {
        Bundle.main.resourceURL?.appendingPathComponent("sites", isDirectory: true)
    }

    func site(for urlString: String) -> SiteConfig? {
        guard let host = URL(string: urlString)?.host else { return nil }
        return sites.first { $0.matches(host: host) }
    }

    func pluginSource(for site: SiteConfig) -> String? {
        guard let plugin = site.plugin, let pluginDirectory else { return nil }
        let file = pluginDirectory.appendingPathComponent(plugin).standardizedFileURL
        guard file.path.hasPrefix(pluginDirectory.standardizedFileURL.path + "/") else { return nil }
        return try? String(contentsOf: file, encoding: .utf8)
    }
}
