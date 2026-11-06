import Foundation

struct DownloadProgress: Equatable {
    var downloadedBytes: Int64?
    var totalBytes: Int64?
    var estimatedTotalBytes: Int64?
    var speed: Double?
    var eta: Int?
    var fragmentIndex: Int?
    var fragmentCount: Int?

    /// 0...1, from exact size, estimated size, or fragment count, in that order.
    var fraction: Double? {
        if let done = downloadedBytes {
            if let total = totalBytes ?? estimatedTotalBytes, total > 0 {
                return min(1, Double(done) / Double(total))
            }
        }
        if let index = fragmentIndex, let count = fragmentCount, count > 0 {
            return min(1, Double(index) / Double(count))
        }
        return nil
    }
}

enum YtDlpEvent: Equatable {
    case title(String)
    case progress(DownloadProgress)
    case file(String)
    case extractor(String)
    case output(String)
}

enum YtDlpOutputParser {
    static func parse(line: String) -> YtDlpEvent {
        if line.hasPrefix(DownloadArguments.progressPrefix) {
            let fields = line.dropFirst(DownloadArguments.progressPrefix.count)
                .split(separator: "|", omittingEmptySubsequences: false)
                .map(String.init)
            func field(_ i: Int) -> String? {
                guard i < fields.count else { return nil }
                let value = fields[i].trimmingCharacters(in: .whitespaces)
                return value == "NA" || value.isEmpty ? nil : value
            }
            func int64(_ i: Int) -> Int64? { field(i).flatMap { Double($0) }.map { Int64($0) } }
            func int(_ i: Int) -> Int? { field(i).flatMap { Double($0) }.map { Int($0) } }
            return .progress(DownloadProgress(
                downloadedBytes: int64(0),
                totalBytes: int64(1),
                estimatedTotalBytes: int64(2),
                speed: field(3).flatMap { Double($0) },
                eta: int(4),
                fragmentIndex: int(5),
                fragmentCount: int(6)
            ))
        }
        if line.hasPrefix(DownloadArguments.titlePrefix) {
            return .title(String(line.dropFirst(DownloadArguments.titlePrefix.count)))
        }
        if line.hasPrefix(DownloadArguments.filePrefix) {
            return .file(String(line.dropFirst(DownloadArguments.filePrefix.count)))
        }
        if line.hasPrefix(DownloadArguments.extractorPrefix) {
            return .extractor(String(line.dropFirst(DownloadArguments.extractorPrefix.count)))
        }
        return .output(line)
    }

    /// One-line reason for a failed download: the last `ERROR:` line, as on the web page.
    static func failureReason(from lines: [String], exitCode: Int32) -> String {
        if let last = lines.last(where: { $0.hasPrefix("ERROR:") }) {
            let reason = last.dropFirst("ERROR:".count).trimmingCharacters(in: .whitespaces)
            if !reason.isEmpty { return reason }
        }
        return "yt-dlp stopped with exit code \(exitCode)"
    }
}
