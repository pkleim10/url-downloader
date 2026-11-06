import AppKit
import SwiftUI

struct SettingsView: View {
    let queue: DownloadQueue

    @AppStorage(SettingsKey.destination) private var destinationPath = ""
    @AppStorage(SettingsKey.maxConcurrent) private var maxConcurrent = AppSettings.defaultMaxConcurrent
    @AppStorage(SettingsKey.quality) private var quality = QualityPreset.configFile
    @AppStorage(SettingsKey.learnSites) private var learnSites = true
    @AppStorage(SettingsKey.autoCheckYtDlp) private var autoCheckYtDlp = false
    @AppStorage(SettingsKey.keepHistory) private var keepHistory = true
    @State private var confirmClearHistory = false

    private var updater: YtDlpUpdater { queue.updater }

    private var versionText: String {
        guard let version = updater.installedVersion else { return queue.ytDlpPath == nil ? "—" : "Reading…" }
        guard let age = updater.ageInDays else { return version }
        return age <= 1 ? "\(version) (released recently)" : "\(version) (\(age) days old)"
    }

    private var statusText: String {
        switch updater.phase {
        case .idle: "Updates fix sites that stopped working."
        case .checking: "Checking GitHub…"
        case .upToDate: "Up to date."
        case .available(let version): "\(version) is available."
        case .updating: "Updating…"
        case .updated(let version): "Updated to \(version)."
        case .failed(let reason): reason
        }
    }

    private var statusColor: Color {
        switch updater.phase {
        case .upToDate, .updated: .green
        case .available: Theme.accent
        case .failed: .orange
        default: .secondary
        }
    }

    var body: some View {
        Form {
            LabeledContent("Save to") {
                HStack {
                    Text(destinationPath.isEmpty ? AppSettings.defaultDestination : destinationPath)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(.secondary)
                    Button("Choose…", action: chooseDestination)
                }
            }
            Stepper(value: $maxConcurrent, in: AppSettings.concurrencyRange) {
                LabeledContent("Downloads at once", value: "\(maxConcurrent)")
            }
            .onChange(of: maxConcurrent) { queue.scheduleDownloads() }
            Picker("Quality", selection: $quality) {
                ForEach(QualityPreset.allCases) { preset in
                    Text(preset.label).tag(preset)
                }
            }
            Toggle(isOn: $keepHistory) {
                Text("Keep download history")
                Text("Lists finished downloads in History and warns before downloading the same video twice. Stored only on this Mac.")
            }
            LabeledContent {
                Button("Clear History…") { confirmClearHistory = true }
                    .disabled(queue.history.entries.isEmpty)
            } label: {
                Text("\(queue.history.entries.count) downloads in history")
                    .foregroundStyle(.secondary)
            }
            .confirmationDialog("Clear all download history?", isPresented: $confirmClearHistory) {
                Button("Clear History", role: .destructive) { queue.history.clear() }
            } message: {
                Text("Downloaded files stay where they are.")
            }
            Toggle(isOn: $learnSites) {
                Text("Learn new sites")
                Text("Siphon tests sites it doesn't know yet, tries automatic fixes when they fail, and records the result in Sites with one example link. Stored only on this Mac.")
            }
            Section("yt-dlp") {
                LabeledContent("Location") {
                    Text(queue.ytDlpPath?.path ?? "Not found")
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                LabeledContent("Version") {
                    Text(versionText)
                        .foregroundStyle(updater.isStale ? Color.orange : Color.secondary)
                }
                if let install = updater.install {
                    LabeledContent("Installed with") {
                        Text("\(install.label) · updates with \(install.commandLine)")
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help(install.commandLine)
                    }
                }
                LabeledContent {
                    HStack(spacing: 8) {
                        if updater.isBusy { ProgressView().controlSize(.small) }
                        Button("Check for Update") { Task { await queue.checkForYtDlpUpdate() } }
                            .disabled(updater.isBusy || queue.ytDlpPath == nil)
                        Button(updater.updateAvailable ? "Update to \(updater.latestVersion ?? "")" : "Update Now") {
                            Task { await queue.updateYtDlp() }
                        }
                        .disabled(updater.isBusy || queue.ytDlpPath == nil)
                    }
                } label: {
                    Text(statusText)
                        .foregroundStyle(statusColor)
                }
                Toggle(isOn: $autoCheckYtDlp) {
                    Text("Check for updates daily")
                    Text("Asks GitHub for the latest yt-dlp version number. Nothing about you or your downloads is sent.")
                }
                if !updater.output.isEmpty {
                    DisclosureGroup("Update output") {
                        ScrollView {
                            Text(updater.output.joined(separator: "\n"))
                                .font(.system(size: 11, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 160)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func chooseDestination() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        panel.directoryURL = URL(fileURLWithPath: AppSettings.destination, isDirectory: true)
        if panel.runModal() == .OK, let url = panel.url {
            destinationPath = url.path
        }
    }
}
