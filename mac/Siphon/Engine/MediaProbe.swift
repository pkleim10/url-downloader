import Foundation

/// Checks a finished download with ffprobe (when installed) before a site is recorded as working.
enum MediaProbe {
    struct Result: Equatable {
        let playable: Bool
        let summary: String
    }

    static func check(path: String?) async -> Result {
        guard let path, let size = fileSize(path) else {
            return Result(playable: true, summary: "yt-dlp reported success; the file wasn't found to inspect.")
        }
        guard let ffprobe = YtDlpLocator.find("ffprobe") else {
            return Result(playable: true, summary: "Downloaded \(Formatters.bytes(size)) (ffprobe isn't installed, so the file wasn't inspected).")
        }
        let output = await Task.detached { run(ffprobe, path: path) }.value
        return summarize(json: output, size: size)
    }

    /// "Downloaded 5.6 MB: H.264 768x432 video, AAC audio, 29.8 s (checked with ffprobe)."
    static func summarize(json: Data?, size: Int64) -> Result {
        struct Probe: Decodable {
            struct Stream: Decodable {
                var codec_type: String?
                var codec_name: String?
                var width: Int?
                var height: Int?
            }
            struct Format: Decodable { var duration: String? }
            var streams: [Stream]?
            var format: Format?
        }
        guard let json, let probe = try? JSONDecoder().decode(Probe.self, from: json),
              let streams = probe.streams, !streams.isEmpty else {
            return Result(playable: false, summary: "Downloaded \(Formatters.bytes(size)), but ffprobe found no audio or video in the file.")
        }
        var parts: [String] = []
        if let video = streams.first(where: { $0.codec_type == "video" }) {
            let dims = video.width.flatMap { w in video.height.map { "\(w)x\($0) " } } ?? ""
            parts.append("\(codecName(video.codec_name)) \(dims)video")
        }
        if let audio = streams.first(where: { $0.codec_type == "audio" }) {
            parts.append("\(codecName(audio.codec_name)) audio")
        }
        if let duration = probe.format?.duration.flatMap(Double.init) {
            parts.append(String(format: "%.1f s", duration))
        }
        let detail = parts.isEmpty ? "" : ": " + parts.joined(separator: ", ")
        if streams.contains(where: { $0.codec_type == "video" }),
           let duration = probe.format?.duration.flatMap(Double.init), duration < shortestVideo {
            return Result(playable: false, summary: "Downloaded \(Formatters.bytes(size))\(detail), too short to be the video; probably a preview clip (checked with ffprobe).")
        }
        return Result(playable: true, summary: "Downloaded \(Formatters.bytes(size))\(detail) (checked with ffprobe).")
    }

    /// Video shorter than this is taken for a preview clip rather than the video itself.
    static let shortestVideo: Double = 8

    private static func codecName(_ name: String?) -> String {
        switch name?.lowercased() {
        case "h264": "H.264"
        case "hevc": "HEVC"
        case "vp9": "VP9"
        case "av1": "AV1"
        case "aac": "AAC"
        case "opus": "Opus"
        case "mp3": "MP3"
        case let other?: other.uppercased()
        case nil: "Unknown"
        }
    }

    private static func fileSize(_ path: String) -> Int64? {
        (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? NSNumber)?.int64Value
    }

    private static func run(_ ffprobe: URL, path: String) -> Data? {
        let process = Process()
        process.executableURL = ffprobe
        process.arguments = [
            "-v", "error", "-of", "json",
            "-show_entries", "format=duration:stream=codec_type,codec_name,width,height",
            path,
        ]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return process.terminationStatus == 0 ? data : nil
    }
}
