import Foundation

/// The persistent sites folder (`sites.json` + `plugins/`) in Application Support.
/// Seeded from the copy bundled with the app, merged with newer bundled entries on every
/// launch, and extended with the sites Siphon learns while downloading.
struct SiteStore {
    let folder: URL

    var fileURL: URL { folder.appendingPathComponent("sites.json") }
    var pluginsURL: URL { folder.appendingPathComponent("plugins", isDirectory: true) }

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
            let merged = Self.merge(user: current, bundled: shipped)
            if merged != current || !FileManager.default.fileExists(atPath: fileURL.path) {
                save(merged)
            }
        }
        return SiteRegistry.load(from: folder)
    }

    func load() -> [SiteConfig] {
        (try? Data(contentsOf: fileURL)).map(SiteRegistry.decode) ?? []
    }

    func save(_ sites: [SiteConfig]) {
        struct File: Encodable { var sites: [SiteConfig] }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(File(sites: sites)) else { return }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }

    /// A bundled entry replaces the entries it overlaps (same id or domain) unless one of
    /// them was tested more recently, so a fix Siphon learned survives an older shipped entry.
    static func merge(user: [SiteConfig], bundled: [SiteConfig]) -> [SiteConfig] {
        var result = user
        for entry in bundled {
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

    /// Bundled plugin files overwrite same-named copies; other plugins are left alone.
    private func copyPlugins(from source: URL) {
        let fm = FileManager.default
        guard let files = fm.enumerator(at: source, includingPropertiesForKeys: [.isRegularFileKey]) else { return }
        for case let file as URL in files {
            guard file.pathComponents.contains("__pycache__") == false,
                  (try? file.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else { continue }
            let relative = String(file.standardizedFileURL.path.dropFirst(source.standardizedFileURL.path.count + 1))
            let target = pluginsURL.appendingPathComponent(relative)
            try? fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            if fm.contentsEqual(atPath: file.path, andPath: target.path) { continue }
            try? fm.removeItem(at: target)
            try? fm.copyItem(at: file, to: target)
        }
    }
}
