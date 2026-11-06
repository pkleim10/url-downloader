import Foundation

/// Runs one yt-dlp process and reports parsed output lines and the exit status on the main queue.
final class DownloadProcess {
    private let process = Process()
    private let outputQueue = DispatchQueue(label: "com.machiilabs.siphon.download-output")
    private let finished = DispatchGroup()
    private var pending: [ObjectIdentifier: Data] = [:]
    private var closed: Set<ObjectIdentifier> = []
    private var recentLines: [String] = []
    private static let keptLines = 200

    private(set) var stoppedByUser = false

    var onEvent: ((YtDlpEvent) -> Void)?
    /// Exit code and the last lines of output (for the failure reason).
    var onExit: ((Int32, [String]) -> Void)?

    init(executable: URL, arguments: [String]) {
        process.executableURL = executable
        process.arguments = arguments
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = YtDlpLocator.childPath
        environment["PYTHONUNBUFFERED"] = "1"
        process.environment = environment
    }

    func start() throws {
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        process.standardInput = FileHandle.nullDevice
        attach(stdout)
        attach(stderr)

        finished.enter()
        process.terminationHandler = { [finished] _ in finished.leave() }
        do {
            try process.run()
        } catch {
            stdout.fileHandleForReading.readabilityHandler = nil
            stderr.fileHandleForReading.readabilityHandler = nil
            throw error
        }

        finished.notify(queue: outputQueue) { [weak self] in
            guard let self else { return }
            let status = self.process.terminationStatus
            let lines = self.recentLines
            DispatchQueue.main.async { self.onExit?(status, lines) }
        }
    }

    /// Interrupts yt-dlp the way Ctrl-C would, so it leaves the `.part` file for resuming.
    func stop() {
        stoppedByUser = true
        guard process.isRunning else { return }
        process.interrupt()
        let process = process
        DispatchQueue.global().asyncAfter(deadline: .now() + 5) {
            if process.isRunning { process.terminate() }
        }
    }

    private func attach(_ pipe: Pipe) {
        finished.enter()
        let key = ObjectIdentifier(pipe)
        pipe.fileHandleForReading.readabilityHandler = { [weak self, outputQueue] handle in
            let data = handle.availableData
            // End of file can be reported more than once before the handler is cleared
            if data.isEmpty { handle.readabilityHandler = nil }
            outputQueue.async {
                if data.isEmpty {
                    self?.close(key)
                } else {
                    self?.consume(data, key: key)
                }
            }
        }
    }

    private func close(_ key: ObjectIdentifier) {
        guard closed.insert(key).inserted else { return }
        flush(key)
        finished.leave()
    }

    private func consume(_ data: Data, key: ObjectIdentifier) {
        var buffer = pending[key, default: Data()]
        buffer.append(data)
        while let index = buffer.firstIndex(where: { $0 == 0x0A || $0 == 0x0D }) {
            let lineData = buffer[buffer.startIndex..<index]
            buffer = Data(buffer[buffer.index(after: index)...])
            emit(lineData)
        }
        pending[key] = buffer
    }

    private func flush(_ key: ObjectIdentifier) {
        if let rest = pending.removeValue(forKey: key), !rest.isEmpty {
            emit(rest)
        }
    }

    private func emit(_ data: Data) {
        guard let line = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespaces),
              !line.isEmpty else { return }
        recentLines.append(line)
        if recentLines.count > Self.keptLines {
            recentLines.removeFirst(recentLines.count - Self.keptLines)
        }
        let event = YtDlpOutputParser.parse(line: line)
        DispatchQueue.main.async { [weak self] in self?.onEvent?(event) }
    }
}
