import Foundation

/// Fetches a page the way a desktop browser does, for sites behind bot checks (Cloudflare)
/// that reject URLSession's network fingerprint whatever its headers. yt-dlp impersonates
/// Chrome and saves the page it received (`--write-pages`); Siphon only reads that file.
enum BrowserFetch {
    /// Desktop Chrome passes Cloudflare reliably; Safari fingerprints and some older Chrome builds don't.
    static let targets = ["chrome-131:macos-14", "chrome-136:macos-15", "chrome-133:macos-15"]
    static let timeout: TimeInterval = 60

    static func page(_ url: URL, referer: String?) async throws -> String {
        guard let ytDlp = YtDlpLocator.ytDlp else { throw RecipeError.pageUnavailable("yt-dlp not found") }
        for target in targets {
            let folder = FileManager.default.temporaryDirectory
                .appendingPathComponent("siphon-page-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: folder) }

            var arguments = ["--ignore-config", "--no-update", "--simulate", "--no-playlist", "--write-pages",
                             "--use-extractors", "generic", "--impersonate", target]
            if let referer { arguments += ["--add-headers", "Referer:\(referer)"] }
            await run(ytDlp, arguments: arguments + ["--", url.absoluteString], in: folder)
            if let html = largestDump(in: folder), !isChallenge(html) { return html }
        }
        throw RecipeError.pageUnavailable("the site's bot check blocked every browser fingerprint")
    }

    static func isChallenge(_ html: String) -> Bool {
        html.contains("challenges.cloudflare.com") && html.count < 20_000
            || html.range(of: "<title>Just a moment", options: .caseInsensitive) != nil
    }

    private static func largestDump(in folder: URL) -> String? {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        let dump = files.filter { $0.pathExtension == "dump" }.max { a, b in
            ((try? a.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
                < ((try? b.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        guard let dump, let data = try? Data(contentsOf: dump) else { return nil }
        return String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
    }

    private static func run(_ executable: URL, arguments: [String], in folder: URL) async {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = folder
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            process.terminationHandler = { _ in continuation.resume() }
            do {
                try process.run()
            } catch {
                process.terminationHandler = nil
                continuation.resume()
                return
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                if process.isRunning { process.terminate() }
            }
        }
    }
}
