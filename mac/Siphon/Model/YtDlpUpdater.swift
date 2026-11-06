import Foundation
import Observation

/// Checks GitHub for a newer yt-dlp and updates it with the command that matches how it was
/// installed. Only contacts GitHub when the user asks, or daily if they turned that on;
/// the request carries nothing about the user.
@MainActor
@Observable
final class YtDlpUpdater {
    enum Phase: Equatable {
        case idle
        case checking
        case upToDate
        case available(String)
        case updating
        case updated(String)
        case failed(String)
    }

    /// Versions older than this get the "update may fix this" banner when downloads fail.
    static let staleAfterDays = 60
    static let releasesURL = URL(string: "https://api.github.com/repos/yt-dlp/yt-dlp/releases/latest")!

    private(set) var phase: Phase = .idle
    private(set) var installedVersion: String?
    private(set) var install: YtDlpInstall?
    private(set) var latestVersion: String?
    private(set) var output: [String] = []

    var ageInDays: Int? { installedVersion.flatMap { YtDlpInstall.ageInDays(of: $0) } }
    var isStale: Bool { (ageInDays ?? 0) > Self.staleAfterDays }
    var isBusy: Bool { phase == .checking || phase == .updating }
    var updateAvailable: Bool {
        guard let latestVersion, let installedVersion else { return false }
        return YtDlpInstall.isNewer(latestVersion, than: installedVersion)
    }

    /// Reads the installed version and install method (runs yt-dlp --version off the main thread).
    func refresh(ytDlp: URL?) async {
        guard let ytDlp else {
            installedVersion = nil
            install = nil
            return
        }
        let (version, kind) = await Task.detached {
            (YtDlpLocator.version(of: ytDlp), YtDlpInstall.detect(ytDlp: ytDlp))
        }.value
        installedVersion = version
        install = kind
    }

    func check(ytDlp: URL?) async {
        guard !isBusy else { return }
        phase = .checking
        await refresh(ytDlp: ytDlp)
        do {
            var request = URLRequest(url: Self.releasesURL, timeoutInterval: 20)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("Siphon", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                throw URLError(.badServerResponse)
            }
            struct Release: Decodable { var tag_name: String }
            let latest = try JSONDecoder().decode(Release.self, from: data).tag_name
            latestVersion = latest
            UserDefaults.standard.set(Date(), forKey: SettingsKey.lastYtDlpCheck)
            phase = updateAvailable ? .available(latest) : .upToDate
        } catch {
            phase = .failed("Couldn't reach GitHub: \(error.localizedDescription)")
        }
    }

    /// Daily check, only when the user turned it on in Settings.
    func checkIfDue(ytDlp: URL?) async {
        guard AppSettings.autoCheckYtDlp else { return }
        let last = UserDefaults.standard.object(forKey: SettingsKey.lastYtDlpCheck) as? Date ?? .distantPast
        guard Date().timeIntervalSince(last) > 86_400 else { return }
        await check(ytDlp: ytDlp)
        if phase == .upToDate { phase = .idle }
    }

    func update(ytDlp: URL?) async {
        guard !isBusy, let ytDlp else { return }
        if install == nil { await refresh(ytDlp: ytDlp) }
        guard let install else { return }
        let before = installedVersion
        phase = .updating
        let command = install.updateCommand
        output = ["$ " + install.commandLine]
        let result = await Task.detached {
            Self.run(command.executable, arguments: command.arguments)
        }.value
        output += result.lines
        await refresh(ytDlp: ytDlp)
        let after = installedVersion ?? "unknown"
        if result.status != 0 {
            phase = .failed(result.lines.last(where: { !$0.isEmpty }) ?? "The update command exited with code \(result.status)")
        } else if let before, after == before {
            if case .homebrew = install {
                phase = .failed("Homebrew doesn't have a newer yt-dlp yet (still \(after)). Try again later.")
            } else if let latestVersion, !YtDlpInstall.isNewer(latestVersion, than: after) {
                phase = .upToDate
            } else {
                phase = .failed("yt-dlp is still \(after) after updating.")
            }
        } else {
            phase = .updated(after)
        }
    }

    nonisolated private static func run(_ executable: String, arguments: [String]) -> (status: Int32, lines: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = YtDlpLocator.childPath
        environment["HOMEBREW_NO_ENV_HINTS"] = "1"
        process.environment = environment
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do { try process.run() } catch {
            return (-1, ["Couldn't run \(executable): \(error.localizedDescription)"])
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let text = String(decoding: data, as: UTF8.self)
        let lines = text.split(omittingEmptySubsequences: false, whereSeparator: { $0 == "\n" || $0 == "\r" })
            .map(String.init).filter { !$0.isEmpty }
        return (process.terminationStatus, lines)
    }
}
