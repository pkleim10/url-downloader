import Foundation

/// The persistent sites folder (`sites.json` + `plugins/`) in Application Support.
/// Seeded from the copy bundled with the app, merged with newer bundled entries on every
/// launch, and extended with the sites Siphon learns while downloading.
struct SiteStore {
    let folder: URL

    var fileURL: URL { folder.appendingPathComponent("sites.json") }
    var pluginsURL: URL { folder.appendingPathComponent("plugins", isDirectory: true) }
    /// Ids the user removed, with the `lastTested` they had, so the bundled copy doesn't bring them back.
    var removedURL: URL { folder.appendingPathComponent("removed.json") }

    static var defaultFolder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Siphon/sites", isDirectory: true)
    }

    /// Brings the persistent copy up to date with `bundled` and returns it as a registry.
    func prepare(bundled: URL?) -> SiteRegistry {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let current = load()
        if let bundled {
            copyPlugins(from: bundled.appendingPathComponent("plugins", isDirectory: true))
            let shipped = SiteRegistry.load(from: bundled).sites
            let merged = Self.merge(user: current, bundled: shipped, removed: loadRemoved())
            // Also rewrites files in an older form (e.g. "embed" entries), since decoding normalizes them.
            if merged != current || (try? Data(contentsOf: fileURL)) != Self.encode(merged) {
                save(merged)
            }
        }
        return SiteRegistry.load(from: folder)
    }

    func load() -> [SiteConfig] {
        (try? Data(contentsOf: fileURL)).map(SiteRegistry.decode) ?? []
    }

    static func encode(_ sites: [SiteConfig]) -> Data? {
        struct File: Encodable { var sites: [SiteConfig] }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try? encoder.encode(File(sites: sites))
    }

    func save(_ sites: [SiteConfig]) {
        guard let data = Self.encode(sites) else { return }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }

    /// Deletes the entry and remembers it, so the bundled copy only brings it back once a newer test ships.
    func remove(_ id: String) {
        var sites = load()
        guard let index = sites.firstIndex(where: { $0.id == id }) else { return }
        var removed = loadRemoved()
        removed[id] = sites[index].lastTested ?? ""
        sites.remove(at: index)
        save(sites)
        if let data = try? JSONEncoder().encode(removed) { try? data.write(to: removedURL, options: .atomic) }
    }

    func loadRemoved() -> [String: String] {
        (try? Data(contentsOf: removedURL)).flatMap { try? JSONDecoder().decode([String: String].self, from: $0) } ?? [:]
    }

    /// A bundled entry replaces the entries it overlaps (same id or domain) unless one of
    /// them was tested more recently, so a fix Siphon learned survives an older shipped entry.
    /// Entries the user removed stay out until the bundle ships one tested later.
    static func merge(user: [SiteConfig], bundled: [SiteConfig], removed: [String: String] = [:]) -> [SiteConfig] {
        var result = user
        for entry in bundled {
            if let removedTested = removed[entry.id], (entry.lastTested ?? "") <= removedTested { continue }
            let overlapping = result.indices.filter { result[$0].overlaps(entry) }
            guard let first = overlapping.first else {
                result.append(entry)
                continue
            }
            let shippedDate = entry.lastTested ?? ""
            if overlapping.contains(where: { (result[$0].lastTested ?? "") > shippedDate }) { continue }
            for index in overlapping.reversed() { result.remove(at: index) }
            result.insert(entry, at: min(first, result.count))
        }
        return result
    }

    /// Bundled plugin files overwrite same-named copies. Files in Siphon's own `plugins/siphon/`
    /// that the bundle no longer ships are removed; plugins anywhere else are left alone.
    private func copyPlugins(from source: URL) {
        let fm = FileManager.default
        let shipped = Self.pluginFiles(in: source)
        for relative in shipped {
            let file = source.appendingPathComponent(relative)
            let target = pluginsURL.appendingPathComponent(relative)
            try? fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            if fm.contentsEqual(atPath: file.path, andPath: target.path) { continue }
            try? fm.removeItem(at: target)
            try? fm.copyItem(at: file, to: target)
        }
        let owned = pluginsURL.appendingPathComponent("siphon", isDirectory: true)
        for relative in Self.pluginFiles(in: owned) where !shipped.contains("siphon/" + relative) {
            try? fm.removeItem(at: owned.appendingPathComponent(relative))
        }
        try? fm.removeItem(at: owned.appendingPathComponent("yt_dlp_plugins/extractor/__pycache__"))
    }

    /// Regular files below `folder`, as paths relative to it, skipping `__pycache__`.
    static func pluginFiles(in folder: URL) -> Set<String> {
        let fm = FileManager.default
        let base = folder.standardizedFileURL.path
        guard let files = fm.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey]) else { return [] }
        var result = Set<String>()
        for case let file as URL in files {
            guard file.pathComponents.contains("__pycache__") == false,
                  (try? file.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else { continue }
            result.insert(String(file.standardizedFileURL.path.dropFirst(base.count + 1)))
        }
        return result
    }
}
