import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class DownloadQueue {
    private(set) var items: [QueueItem] = []
    private(set) var sites: SiteRegistry
    private(set) var ytDlpPath: URL?

    @ObservationIgnored private var processes: [UUID: DownloadProcess] = [:]
    /// Processes asked to stop that haven't exited yet; their item can't restart until they do,
    /// or two yt-dlp processes would write the same partial file.
    @ObservationIgnored private var stopping: [UUID: DownloadProcess] = [:]
    @ObservationIgnored private let store: QueueStore

    init(store: QueueStore = QueueStore(fileURL: QueueStore.defaultFileURL),
         sites: SiteRegistry = .load(from: SiteRegistry.bundledFolder)) {
        self.store = store
        self.sites = sites
        items = store.load()
        ytDlpPath = YtDlpLocator.ytDlp
        scheduleDownloads()
    }

    var activeCount: Int { items.filter { $0.status == .downloading }.count }
    var hasPausable: Bool { items.contains { $0.status == .downloading || $0.status == .pending } }
    var hasPaused: Bool { items.contains { $0.status == .paused } }
    var hasCompleted: Bool { items.contains { $0.status == .completed } }

    // MARK: - Adding

    /// Adds every link found in `text`; returns how many were added.
    @discardableResult
    func add(text: String, prefix: String = "", destination: String = AppSettings.destination) -> Int {
        let links = LinkExtractor.links(in: text)
        for link in links {
            var item = QueueItem(url: link, prefix: prefix, destination: destination)
            item.siteName = sites.site(for: link)?.name
            items.append(item)
        }
        if !links.isEmpty {
            save()
            scheduleDownloads()
        }
        return links.count
    }

    // MARK: - Per-item actions

    func pause(_ id: UUID) {
        guard let i = index(of: id) else { return }
        switch items[i].status {
        case .downloading:
            stopProcess(id)
            items[i].status = .paused
            items[i].speed = nil
            items[i].eta = nil
        case .pending, .failed:
            items[i].status = .paused
        default:
            return
        }
        save()
        scheduleDownloads()
    }

    /// Unpauses an item; it starts as soon as a slot is free.
    func resume(_ id: UUID) {
        guard let i = index(of: id), items[i].status == .paused else { return }
        items[i].status = .pending
        save()
        scheduleDownloads()
    }

    /// Returns a failed item to the queue and clears its failure reason.
    func retry(_ id: UUID) {
        guard let i = index(of: id), items[i].status == .failed else { return }
        items[i].status = .pending
        items[i].failReason = nil
        items[i].clearProgress()
        save()
        scheduleDownloads()
    }

    func remove(_ id: UUID) {
        stopProcess(id)
        items.removeAll { $0.id == id }
        save()
        scheduleDownloads()
    }

    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        items.move(fromOffsets: source, toOffset: destination)
        save()
    }

    // MARK: - Whole-queue actions

    func pauseAll() {
        for i in items.indices where items[i].status == .downloading || items[i].status == .pending {
            if items[i].status == .downloading { stopProcess(items[i].id) }
            items[i].status = .paused
            items[i].speed = nil
            items[i].eta = nil
        }
        save()
        updateDockBadge()
    }

    func resumeAll() {
        for i in items.indices where items[i].status == .paused {
            items[i].status = .pending
        }
        save()
        scheduleDownloads()
    }

    func clearCompleted() {
        items.removeAll { $0.status == .completed }
        save()
    }

    func clearAll() {
        for id in Array(processes.keys) { stopProcess(id) }
        items.removeAll()
        save()
        updateDockBadge()
    }

    /// Stops running downloads (keeping partial files) when the app quits.
    func shutdown() {
        for process in processes.values { process.stop() }
        save()
    }

    func reloadSites() {
        sites = .load(from: SiteRegistry.bundledFolder)
        ytDlpPath = YtDlpLocator.ytDlp
    }

    // MARK: - Scheduling

    func scheduleDownloads() {
        for id in QueueScheduler.itemsToStart(in: items, limit: AppSettings.maxConcurrent) {
            start(id)
        }
        updateDockBadge()
    }

    private func start(_ id: UUID) {
        guard let i = index(of: id), stopping[id] == nil else { return }
        guard let ytDlp = ytDlpPath ?? YtDlpLocator.ytDlp else {
            fail(id, reason: "yt-dlp not found. Install it with: brew install yt-dlp")
            return
        }
        ytDlpPath = ytDlp

        let item = items[i]
        let site = sites.site(for: item.url)
        let destination = URL(fileURLWithPath: item.destination, isDirectory: true)
        try? FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let arguments = DownloadArguments.build(
            url: item.url,
            prefix: item.prefix,
            destination: destination,
            site: site,
            pluginDirectory: sites.pluginDirectory,
            quality: AppSettings.quality
        )

        let process = DownloadProcess(executable: ytDlp, arguments: arguments)
        process.onEvent = { [weak self] event in self?.handle(event, for: id) }
        process.onExit = { [weak self, weak process] code, lines in
            guard let self, let process else { return }
            self.finish(id, process: process, exitCode: code, lines: lines)
        }

        items[i].status = .downloading
        items[i].siteName = site?.name
        items[i].failReason = nil
        items[i].clearProgress()
        processes[id] = process
        do {
            try process.start()
        } catch {
            processes[id] = nil
            fail(id, reason: "Could not start yt-dlp: \(error.localizedDescription)")
        }
    }

    private func handle(_ event: YtDlpEvent, for id: UUID) {
        guard let i = index(of: id), items[i].status == .downloading else { return }
        switch event {
        case .title(let title):
            items[i].title = title
            save()
        case .progress(let progress):
            items[i].downloadedBytes = progress.downloadedBytes
            items[i].totalBytes = progress.totalBytes ?? progress.estimatedTotalBytes
            items[i].speed = progress.speed
            items[i].eta = progress.eta
            if let fraction = progress.fraction { items[i].fraction = fraction }
        case .file(let path):
            items[i].filePath = path
        case .output:
            break
        }
    }

    private func finish(_ id: UUID, process: DownloadProcess, exitCode: Int32, lines: [String]) {
        if processes[id] === process { processes[id] = nil }
        if stopping[id] === process { stopping[id] = nil }
        defer { scheduleDownloads() }
        guard !process.stoppedByUser, let i = index(of: id), items[i].status == .downloading else { return }
        if exitCode == 0 {
            items[i].status = .completed
            items[i].fraction = 1
            items[i].speed = nil
            items[i].eta = nil
        } else {
            items[i].status = .failed
            items[i].failReason = YtDlpOutputParser.failureReason(from: lines, exitCode: exitCode)
            items[i].clearProgress()
        }
        save()
    }

    private func stopProcess(_ id: UUID) {
        guard let process = processes.removeValue(forKey: id) else { return }
        stopping[id] = process
        process.stop()
    }

    private func fail(_ id: UUID, reason: String) {
        guard let i = index(of: id) else { return }
        items[i].status = .failed
        items[i].failReason = reason
        items[i].clearProgress()
        save()
    }

    private func index(of id: UUID) -> Int? {
        items.firstIndex { $0.id == id }
    }

    private func save() {
        store.save(items)
    }

    private func updateDockBadge() {
        let active = activeCount
        NSApp?.dockTile.badgeLabel = active > 0 ? "\(active)" : nil
    }
}
