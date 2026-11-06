import AppKit
import SwiftUI

struct SettingsView: View {
    let queue: DownloadQueue

    @AppStorage(SettingsKey.destination) private var destinationPath = ""
    @AppStorage(SettingsKey.maxConcurrent) private var maxConcurrent = AppSettings.defaultMaxConcurrent
    @AppStorage(SettingsKey.quality) private var quality = QualityPreset.configFile
    @AppStorage(SettingsKey.learnSites) private var learnSites = true

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
            Toggle(isOn: $learnSites) {
                Text("Learn new sites")
                Text("Siphon tests sites it doesn't know yet, tries automatic fixes when they fail, and records the result in Sites with one example link. Stored only on this Mac.")
            }
            LabeledContent("yt-dlp") {
                Text(queue.ytDlpPath?.path ?? "Not found")
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
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
