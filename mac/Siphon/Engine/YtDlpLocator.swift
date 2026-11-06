import Foundation

/// Finds the installed yt-dlp and ffmpeg. Apps launched from Finder get a minimal PATH,
/// so the usual Homebrew and pip locations are checked explicitly.
enum YtDlpLocator {
    static let searchDirectories = [
        "/opt/homebrew/bin",
        "/usr/local/bin",
        NSHomeDirectory() + "/.local/bin",
        "/usr/bin",
    ]

    static func find(_ tool: String, in directories: [String] = searchDirectories) -> URL? {
        let pathDirectories = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":").map(String.init)
        for directory in directories + pathDirectories {
            let candidate = URL(fileURLWithPath: directory).appendingPathComponent(tool)
            if FileManager.default.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }

    static var ytDlp: URL? { find("yt-dlp") }

    /// PATH for the yt-dlp child process, so it can find ffmpeg for merging.
    static var childPath: String {
        var directories = searchDirectories
        if let current = ProcessInfo.processInfo.environment["PATH"] {
            directories += current.split(separator: ":").map(String.init)
        }
        var seen = Set<String>()
        return directories.filter { seen.insert($0).inserted }.joined(separator: ":")
    }

    static func version(of executable: URL) -> String? {
        let process = Process()
        process.executableURL = executable
        process.arguments = ["--version"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            return nil
        }
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
