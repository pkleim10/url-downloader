import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class DownloadQueue {
    private(set) var items: [QueueItem] = []
    private(set) var sites: SiteRegistry
    private(set) var ytDlpPath: URL?
    /// The yt-dlp command and output for each item since launch, newest attempt last; not saved.
    private(set) var logs: [UUID: [String]] = [:]
    static let logLimit = 1000
    let updater = YtDlpUpdater()
    let history: DownloadHistory
    /// How many links the last `add` paused because they were downloaded before.
    private(set) var lastAddHeldDuplicates = 0
    @ObservationIgnored private var videoKeys: [UUID: String] = [:]
    /// Player iframes found for items on sites that embed another host's player.
    @ObservationIgnored private var embeds: [UUID: URL] = [:]
    @ObservationIgnored private var observations: [UUID: RecipeObservation] = [:]
    /// The pending iframe lookup per item; a stale lookup (item paused or restarted) is ignored.
    @ObservationIgnored private var embedLookups: [UUID: UUID] = [:]

    @ObservationIgnored private var processes: [UUID: DownloadProcess] = [:]
    /// Processes asked to stop that haven't exited yet; their item can't restart until they do,
    /// or two yt-dlp processes would write the same partial file.
    @ObservationIgnored private var stopping: [UUID: DownloadProcess] = [:]
    @ObservationIgnored private let store: QueueStore
    @ObservationIgnored private let siteStore: SiteStore
    @ObservationIgnored private let bundledSites: URL?
    /// Items whose site is being tested: which attempts remain and what failed so far.
    @ObservationIgnored private var learning: [UUID: LearningState] = [:]

    private struct LearningState {
        var attempts: [SiteLearner.Attempt]
        var index = 0
        var existing: SiteConfig?
        var extractor: String?
        var firstFailure: String?

        var current: SiteLearner.Attempt { attempts[index] }
    }

    init(store: QueueStore = QueueStore(fileURL: QueueStore.defaultFileURL),
         siteStore: SiteStore = SiteStore(folder: SiteStore.defaultFolder),
         bundledSites: URL? = SiteRegistry.bundledFolder,
         history: DownloadHistory? = nil) {
        self.store = store
        self.history = history ?? DownloadHistory()
        self.siteStore = siteStore
        self.bundledSites = bundledSites
        sites = siteStore.prepare(bundled: bundledSites)
        items = store.load()
        ytDlpPath = YtDlpLocator.ytDlp
        scheduleDownloads()
        Task { [updater, ytDlpPath] in
            await updater.refresh(ytDlp: ytDlpPath)
            await updater.checkIfDue(ytDlp: ytDlpPath)
        }
    }

    var hasFailed: Bool { items.contains { $0.status == .failed } }

    /// Queues a link from History again, skipping the duplicate check.
    func downloadAgain(_ entry: HistoryEntry) {
        var item = QueueItem(url: entry.url, destination: AppSettings.destination)
        item.siteName = sites.site(for: entry.url)?.name
        item.title = entry.title
        item.allowDuplicate = true
        items.append(item)
        save()
        scheduleDownloads()
    }

    func retryAllFailed() {
        for i in items.indices where items[i].status == .failed {
            items[i].status = .pending
            items[i].failReason = nil
            items[i].note = nil
            items[i].clearProgress()
        }
        save()
        scheduleDownloads()
    }

    func checkForYtDlpUpdate() async {
        await updater.check(ytDlp: ytDlpPath ?? YtDlpLocator.ytDlp)
    }

    func updateYtDlp() async {
        await updater.update(ytDlp: ytDlpPath ?? YtDlpLocator.ytDlp)
        ytDlpPath = YtDlpLocator.ytDlp
    }

    var activeCount: Int { items.filter { $0.status == .downloading }.count }
    var hasPausable: Bool { items.contains { $0.status == .downloading || $0.status == .pending } }
    var hasPaused: Bool { items.contains { $0.status == .paused && $0.heldAsDuplicate != true } }
    var hasCompleted: Bool { items.contains { $0.status == .completed } }

    // MARK: - Adding

    /// Adds every link found in `text`; returns how many were added.
    @discardableResult
    func add(text: String, prefix: String = "", destination: String = AppSettings.destination) -> Int {
        let links = LinkExtractor.links(in: text)
        lastAddHeldDuplicates = 0
        for link in links {
            var item = QueueItem(url: link, prefix: prefix, destination: destination)
            item.siteName = sites.site(for: link)?.name
            if let earlier = history.duplicate(ofURL: link) {
                item.status = .paused
                item.heldAsDuplicate = true
                item.title = earlier.title
                lastAddHeldDuplicates += 1
            }
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
        if items[i].heldAsDuplicate == true {
            items[i].heldAsDuplicate = nil
            items[i].allowDuplicate = true
        }
        items[i].status = .pending
        save()
        scheduleDownloads()
    }

    /// Returns a failed item to the queue and clears its failure reason.
    func retry(_ id: UUID) {
        guard let i = index(of: id), items[i].status == .failed else { return }
        items[i].status = .pending
        items[i].failReason = nil
        items[i].note = nil
        items[i].clearProgress()
        embeds[id] = nil
        observations[id] = nil
        save()
        scheduleDownloads()
    }

    func remove(_ id: UUID) {
        stopProcess(id)
        learning[id] = nil
        logs[id] = nil
        videoKeys[id] = nil
        embeds[id] = nil
        observations[id] = nil
        embedLookups[id] = nil
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

    /// Items held as duplicates stay paused; they only download when resumed one by one.
    func resumeAll() {
        for i in items.indices where items[i].status == .paused && items[i].heldAsDuplicate != true {
            items[i].status = .pending
        }
        save()
        scheduleDownloads()
    }

    func clearCompleted() {
        for item in items where item.status == .completed { logs[item.id] = nil }
        items.removeAll { $0.status == .completed }
        save()
    }

    func clearAll() {
        for id in Array(processes.keys) { stopProcess(id) }
        learning.removeAll()
        logs.removeAll()
        embeds.removeAll()
        observations.removeAll()
        embedLookups.removeAll()
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
        sites = siteStore.prepare(bundled: bundledSites)
        ytDlpPath = YtDlpLocator.ytDlp
    }

    var sitesFolder: URL { siteStore.folder }

    func removeSite(_ id: String) {
        siteStore.remove(id)
        sites = .load(from: siteStore.folder)
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
        if learning[id] == nil, AppSettings.learnSites, SiteLearner.shouldLearn(site) {
            learning[id] = LearningState(attempts: SiteLearner.attempts(for: item.url, existing: site), existing: site)
        }
        let siteArguments = learning[id]?.current.arguments ?? site?.ytDlpArgs ?? []
        let recipe = learning[id].map { $0.current.recipe } ?? site?.recipe

        items[i].status = .downloading
        items[i].siteName = site?.name
        items[i].failReason = nil
        items[i].clearProgress()
        if let state = learning[id] {
            items[i].note = state.index == 0
                ? (site == nil ? "New site: testing" : "Retesting site")
                : "Trying fix \(state.index) of \(state.attempts.count - 1): \(state.current.label)"
        } else {
            items[i].note = nil
        }
        if logs[id] != nil { appendLog(id, "") }
        if let state = learning[id], state.index > 0 {
            appendLog(id, "--- Trying fix \(state.index) of \(state.attempts.count - 1): \(state.current.label)")
        }

        observations[id] = nil
        guard let recipe else {
            launch(id, ytDlp: ytDlp, url: item.url, siteArguments: siteArguments)
            return
        }
        guard let page = URL(string: item.url) else {
            attemptFailed(id, reason: RecipeError.noEmbed.localizedDescription)
            return
        }
        appendLog(id, "--- Running the site recipe" + (recipe.media == .sources ? " (reading the player's video sources)" : ""))
        let token = UUID()
        embedLookups[id] = token
        let quality = AppSettings.quality
        Task { [weak self] in
            let result: Result<RecipeResolution, Error>
            do {
                result = .success(try await RecipeRunner.resolve(page: page, recipe: recipe, quality: quality))
            } catch {
                result = .failure(error)
            }
            guard let self, self.embedLookups[id] == token else { return }
            self.embedLookups[id] = nil
            guard let i = self.index(of: id), self.items[i].status == .downloading else { return }
            switch result {
            case .success(let resolution):
                self.embeds[id] = resolution.embedURL
                self.observations[id] = resolution.observed
                if let embed = resolution.embedURL { self.appendLog(id, "--- Found the player: \(embed.absoluteString)") }
                if let title = resolution.title { self.appendLog(id, "--- Title: \(title)") }
                if recipe.media == .sources {
                    self.appendLog(id, "--- Video: \(resolution.url.absoluteString)"
                        + (resolution.sourceLabel.map { " (\($0))" } ?? ""))
                }
                self.launch(id, ytDlp: ytDlp, url: resolution.url.absoluteString,
                            siteArguments: siteArguments + RecipeRunner.arguments(for: resolution))
            case .failure(let error):
                self.appendLog(id, "--- " + error.localizedDescription)
                self.attemptFailed(id, reason: error.localizedDescription)
                self.scheduleDownloads()
            }
        }
    }

    private func launch(_ id: UUID, ytDlp: URL, url: String, siteArguments: [String]) {
        guard let item = items.first(where: { $0.id == id }) else { return }
        let destination = URL(fileURLWithPath: item.destination, isDirectory: true)
        try? FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let arguments = DownloadArguments.build(
            url: url,
            prefix: item.prefix,
            destination: destination,
            siteArguments: siteArguments,
            pluginDirectory: sites.pluginDirectory,
            quality: AppSettings.quality
        )
        appendLog(id, "$ " + ([ytDlp.path] + arguments).map(Self.shellQuoted).joined(separator: " "))
        let process = DownloadProcess(executable: ytDlp, arguments: arguments)
        process.onEvent = { [weak self] event in self?.handle(event, for: id) }
        process.onExit = { [weak self, weak process] code, lines in
            guard let self, let process else { return }
            self.finish(id, process: process, exitCode: code, lines: lines)
        }
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
        case .extractor(let name, let videoID, let inPlaylist):
            learning[id]?.extractor = name
            // Generic ids are just file names, which unrelated sites reuse.
            guard !inPlaylist, name != "Generic", let videoID else { break }
            let key = "\(name):\(videoID)"
            videoKeys[id] = key
            if items[i].allowDuplicate != true, let earlier = history.duplicate(ofVideoKey: key) {
                holdAsDuplicate(id, earlier: earlier)
            }
        case .output(let line):
            appendLog(id, line)
        }
    }

    private func finish(_ id: UUID, process: DownloadProcess, exitCode: Int32, lines: [String]) {
        if processes[id] === process { processes[id] = nil }
        if stopping[id] === process { stopping[id] = nil }
        defer { scheduleDownloads() }
        appendLog(id, process.stoppedByUser ? "--- Stopped" : "--- yt-dlp exited with code \(exitCode)")
        guard !process.stoppedByUser, let i = index(of: id), items[i].status == .downloading else { return }
        if exitCode == 0 {
            items[i].status = .completed
            items[i].fraction = 1
            items[i].speed = nil
            items[i].eta = nil
            if AppSettings.keepHistory {
                history.record(HistoryEntry(
                    url: items[i].url, title: items[i].title, filePath: items[i].filePath,
                    siteName: items[i].siteName, videoKey: videoKeys[id],
                    sizeBytes: items[i].filePath.flatMap(Self.fileSize), downloadedAt: Date()))
            }
            videoKeys[id] = nil
            if let state = learning.removeValue(forKey: id) {
                items[i].note = "Checking the file…"
                recordSuccess(id, url: items[i].url, path: items[i].filePath, state: state, embedURL: embeds[id],
                              observed: observations[id])
            }
        } else {
            attemptFailed(id, reason: YtDlpOutputParser.failureReason(from: lines, exitCode: exitCode))
            return
        }
        save()
    }

    /// While a site is being learned, moves on to the next fix; otherwise marks the item failed.
    private func attemptFailed(_ id: UUID, reason: String) {
        guard let i = index(of: id) else { return }
        if var state = learning[id] {
            let kind = SiteLearner.classify(reason)
            if state.firstFailure == nil { state.firstFailure = reason }
            if kind == .site, state.index + 1 < state.attempts.count {
                state.index += 1
                learning[id] = state
                items[i].status = .pending
                items[i].note = "Trying fix \(state.index) of \(state.attempts.count - 1): \(state.current.label)"
                items[i].clearProgress()
                save()
                return
            }
            learning[id] = nil
            if kind == .site || kind == .drm,
               let entry = SiteLearner.failedEntry(
                   url: items[i].url, kind: kind, tried: Array(state.attempts[...state.index]),
                   firstFailure: state.firstFailure, lastFailure: reason, existing: state.existing) {
                recordSite(entry)
                items[i].note = kind == .drm ? "Recorded in Sites as unsupported (DRM)" : "Recorded in Sites as broken"
            } else {
                items[i].note = nil
            }
        }
        items[i].status = .failed
        items[i].failReason = reason
        items[i].clearProgress()
        save()
    }

    // MARK: - Learning sites

    private func recordSuccess(_ id: UUID, url: String, path: String?, state: LearningState, embedURL: URL?,
                               observed: RecipeObservation?) {
        Task { [weak self] in
            let check = await MediaProbe.check(path: path)
            guard let self else { return }
            let i = self.index(of: id)
            if check.playable {
                if let entry = SiteLearner.workingEntry(
                    url: url, attempt: state.current, extractor: state.extractor,
                    firstFailure: state.firstFailure, testResult: check.summary, existing: state.existing,
                    embedURL: embedURL, observed: observed) {
                    self.recordSite(entry)
                }
                if let i { self.items[i].note = state.existing == nil ? "Added to Sites" : "Sites entry updated" }
            } else {
                if let entry = SiteLearner.failedEntry(
                    url: url, kind: .site, tried: [state.current], firstFailure: state.firstFailure,
                    lastFailure: check.summary, existing: state.existing) {
                    self.recordSite(entry)
                }
                if let i {
                    self.items[i].status = .failed
                    self.items[i].failReason = check.summary
                    self.items[i].note = "Recorded in Sites as broken"
                }
            }
            self.save()
        }
    }

    /// Replaces any learned entry for the same domain; curated entries are never touched.
    private func recordSite(_ entry: SiteConfig) {
        var all = siteStore.load()
        all.removeAll { $0.isLearned && $0.overlaps(entry) }
        all.append(entry)
        siteStore.save(all)
        sites = .load(from: siteStore.folder)
        for i in items.indices where items[i].siteName == nil && sites.site(for: items[i].url)?.id == entry.id {
            items[i].siteName = entry.name
        }
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

    private func holdAsDuplicate(_ id: UUID, earlier: HistoryEntry) {
        guard let i = index(of: id) else { return }
        stopProcess(id)
        items[i].status = .paused
        items[i].heldAsDuplicate = true
        items[i].clearProgress()
        appendLog(id, "--- Same video as \"\(earlier.displayTitle)\", downloaded \(earlier.downloadedAt.formatted(date: .abbreviated, time: .shortened)). Paused; resume to download it again.")
        save()
    }

    nonisolated static func fileSize(_ path: String) -> Int64? {
        (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? NSNumber)?.int64Value
    }

    private func appendLog(_ id: UUID, _ line: String) {
        guard items.contains(where: { $0.id == id }) else { return }
        var lines = logs[id] ?? []
        lines.append(line)
        if lines.count > Self.logLimit { lines.removeFirst(lines.count - Self.logLimit) }
        logs[id] = lines
    }

    static func shellQuoted(_ argument: String) -> String {
        let safe = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_./:=@%+,"))
        if !argument.isEmpty, argument.unicodeScalars.allSatisfy(safe.contains) { return argument }
        return "'" + argument.replacingOccurrences(of: "'", with: "'\\''") + "'"
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
