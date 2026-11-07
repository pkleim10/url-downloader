import Foundation

/// Video quality choices offered in Settings, mapped to yt-dlp format selectors.
enum QualityPreset: String, CaseIterable, Identifiable, Codable {
    case configFile, best, p2160, p1440, p1080, p720, audioOnly

    var id: String { rawValue }

    var label: String {
        switch self {
        case .configFile: "Use my yt-dlp config"
        case .best: "Best available"
        case .p2160: "Up to 4K"
        case .p1440: "Up to 1440p"
        case .p1080: "Up to 1080p"
        case .p720: "Up to 720p"
        case .audioOnly: "Audio only"
        }
    }

    /// Empty leaves the format to the user's yt-dlp config file.
    var formatArguments: [String] {
        switch self {
        case .configFile: []
        case .best: ["-f", Self.labelledHigh + "bv*+ba/b"]
        case .p2160: ["-f", Self.labelledHigh + "bv*[height<=2160]+ba/b[height<=2160]/b"]
        case .p1440: ["-f", Self.labelledHigh + "bv*[height<=1440]+ba/b[height<=1440]/b"]
        case .p1080: ["-f", Self.labelledHigh + "bv*[height<=1080]+ba/b[height<=1080]/b"]
        case .p720: ["-f", Self.labelledHigh + "bv*[height<=720]+ba/b[height<=720]/b"]
        case .audioOnly: ["-f", "ba/b", "-x"]
        }
    }

    /// When a page's formats carry no height, yt-dlp ranks them by list order, so a player that
    /// lists "HQ" before "LQ" downloads the low one. `[height<?1]` keeps only formats of unknown
    /// height, so sites that report heights are unaffected.
    private static let labelledHigh = "b[height<?1][format_id~='(?i)(^|_)(hq|high|hd)(_|$)']/"
}

enum DownloadArguments {
    static let progressPrefix = "SIPHON-PROGRESS "
    static let titlePrefix = "SIPHON-TITLE "
    static let filePrefix = "SIPHON-FILE "
    static let extractorPrefix = "SIPHON-EXTRACTOR "

    /// Same rule as the web server: letters, digits, space, underscore and hyphen only.
    static func sanitizePrefix(_ prefix: String) -> String {
        String(prefix.map { ch in
            ch.isASCII && (ch.isLetter || ch.isNumber || ch == "_" || ch == " " || ch == "-") ? ch : "_"
        })
    }

    static func outputTemplate(destination: URL, prefix: String) -> String {
        let clean = sanitizePrefix(prefix.trimmingCharacters(in: .whitespaces))
        let name = clean.isEmpty ? "%(title)s.%(ext)s" : "\(clean)-%(title)s.%(ext)s"
        return destination.appendingPathComponent(name).path
    }

    /// Full yt-dlp argument list. Machine-readable lines (title, progress, final path)
    /// are tagged so `YtDlpOutputParser` can pick them out of yt-dlp's normal output.
    static func build(
        url: String,
        prefix: String,
        destination: URL,
        siteArguments: [String],
        pluginDirectory: URL?,
        quality: QualityPreset
    ) -> [String] {
        var args: [String] = []
        if let pluginDirectory {
            args += ["--plugin-dirs", pluginDirectory.path]
        }
        args += siteArguments
        args += quality.formatArguments
        args += [
            "--no-update",
            "--progress", "--newline", "--no-simulate",
            "--progress-template",
            "download:\(progressPrefix)%(progress.downloaded_bytes)s|%(progress.total_bytes)s|%(progress.total_bytes_estimate)s|%(progress.speed)s|%(progress.eta)s|%(progress.fragment_index)s|%(progress.fragment_count)s",
            "--print", "before_dl:\(titlePrefix)%(title)s",
            "--print", "before_dl:\(extractorPrefix)%(extractor_key)s|%(id)s|%(playlist_index)s",
            "--print", "after_move:\(filePrefix)%(filepath)s",
            "-o", outputTemplate(destination: destination, prefix: prefix),
            "--", url,
        ]
        return args
    }
}
