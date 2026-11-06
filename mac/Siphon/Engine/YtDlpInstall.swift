import Foundation

/// How the installed yt-dlp got there, which decides the command that updates it.
enum YtDlpInstall: Equatable {
    case homebrew(brew: String)
    case pipx(pipx: String)
    case pip(python: String)
    case standalone(ytDlp: String)

    var label: String {
        switch self {
        case .homebrew: "Homebrew"
        case .pipx: "pipx"
        case .pip: "pip"
        case .standalone: "Standalone binary"
        }
    }

    /// Executable and arguments that update yt-dlp in place.
    var updateCommand: (executable: String, arguments: [String]) {
        switch self {
        case .homebrew(let brew): (brew, ["upgrade", "yt-dlp"])
        case .pipx(let pipx): (pipx, ["upgrade", "yt-dlp"])
        case .pip(let python): (python, ["-m", "pip", "install", "--upgrade", "yt-dlp"])
        case .standalone(let ytDlp): (ytDlp, ["-U"])
        }
    }

    var commandLine: String {
        let command = updateCommand
        return ([command.executable] + command.arguments).joined(separator: " ")
    }

    /// `resolvedPath` is the yt-dlp path with symlinks resolved; `head` is the file's first bytes.
    static func detect(resolvedPath: String, head: Data, brew: String?, pipx: String?) -> YtDlpInstall {
        if resolvedPath.contains("/Cellar/yt-dlp/"), let brew {
            return .homebrew(brew: brew)
        }
        if let line = shebang(head) {
            if resolvedPath.contains("/pipx/") || line.contains("/pipx/"), let pipx {
                return .pipx(pipx: pipx)
            }
            let interpreter = line.split(separator: " ").first.map(String.init) ?? line
            if interpreter.contains("python") {
                return .pip(python: interpreter)
            }
        }
        return .standalone(ytDlp: resolvedPath)
    }

    static func detect(ytDlp: URL) -> YtDlpInstall {
        let resolved = ytDlp.resolvingSymlinksInPath().path
        let head = (try? FileHandle(forReadingFrom: URL(fileURLWithPath: resolved)))
            .flatMap { handle in defer { try? handle.close() }; return try? handle.read(upToCount: 256) } ?? Data()
        return detect(resolvedPath: resolved, head: head,
                      brew: YtDlpLocator.find("brew")?.path, pipx: YtDlpLocator.find("pipx")?.path)
    }

    private static func shebang(_ head: Data) -> String? {
        guard head.starts(with: Array("#!".utf8)),
              let text = String(data: head, encoding: .utf8) ?? String(data: head, encoding: .isoLatin1),
              let line = text.split(separator: "\n").first else { return nil }
        return line.dropFirst(2).trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Versions

    /// yt-dlp versions are dates with an optional build suffix: "2026.10.26" or "2026.10.26.232815".
    static func isNewer(_ candidate: String, than installed: String) -> Bool {
        let a = components(candidate), b = components(installed)
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0, y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    static func releaseDate(of version: String) -> Date? {
        let parts = components(version)
        guard parts.count >= 3 else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    static func ageInDays(of version: String, now: Date = Date()) -> Int? {
        releaseDate(of: version).map { Int(now.timeIntervalSince($0) / 86_400) }
    }

    private static func components(_ version: String) -> [Int] {
        version.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: ".").map { Int($0.filter(\.isNumber)) ?? 0 }
    }
}
