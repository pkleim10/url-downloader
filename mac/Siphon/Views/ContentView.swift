import AppKit
import SwiftUI

struct ContentView: View {
    let queue: DownloadQueue

    @Environment(\.openWindow) private var openWindow
    @AppStorage(SettingsKey.destination) private var destinationPath = ""
    @AppStorage(SettingsKey.maxConcurrent) private var maxConcurrent = AppSettings.defaultMaxConcurrent
    @State private var linkText = ""
    @State private var prefix = ""
    @State private var addHint: String?
    @State private var confirmClearAll = false
    @FocusState private var linkFieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            addBar
            Divider()
            if queue.ytDlpPath == nil {
                missingYtDlpBanner
            }
            if queue.items.isEmpty {
                ContentUnavailableView(
                    "No downloads",
                    systemImage: "arrow.down.circle",
                    description: Text("Paste links above, or drop them on this window.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(queue.items) { item in
                        QueueRow(item: item, queue: queue)
                    }
                    .onMove { queue.move(fromOffsets: $0, toOffset: $1) }
                }
                .listStyle(.inset)
            }
        }
        .frame(minWidth: 560, minHeight: 360)
        .toolbar { toolbarContent }
        .dropDestination(for: URL.self) { urls, _ in
            queue.add(text: urls.map(\.absoluteString).joined(separator: "\n"))
        }
        .confirmationDialog("Remove every item from the queue?", isPresented: $confirmClearAll) {
            Button("Clear All", role: .destructive) { queue.clearAll() }
        } message: {
            Text("Running downloads stop. Files already downloaded stay where they are.")
        }
        .onAppear { linkFieldFocused = true }
    }

    // MARK: - Add bar

    private var addBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                TextField("Paste one or more links", text: $linkText, axis: .vertical)
                    .lineLimit(1...4)
                    .textFieldStyle(.roundedBorder)
                    .focused($linkFieldFocused)
                    .onSubmit(addLinks)
                Button("Add", action: addLinks)
                    .disabled(linkText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            HStack(spacing: 8) {
                TextField("Filename prefix (optional)", text: $prefix)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 220)
                Button {
                    chooseDestination()
                } label: {
                    Label(destinationName, systemImage: "folder")
                }
                .help("Save to \(AppSettings.destination)")
                Spacer()
                if let addHint {
                    Text(addHint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
    }

    private var destinationName: String {
        let path = destinationPath.isEmpty ? AppSettings.defaultDestination : destinationPath
        return FileManager.default.displayName(atPath: path)
    }

    private var missingYtDlpBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
            Text("yt-dlp isn't installed. Install it with Homebrew: brew install yt-dlp")
            Spacer()
            Button("Check Again") { queue.reloadSites() }
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.yellow.opacity(0.12))
    }

    private func addLinks() {
        let added = queue.add(text: linkText, prefix: prefix, destination: AppSettings.destination)
        if added > 0 {
            linkText = ""
            addHint = added == 1 ? "Added 1 link" : "Added \(added) links"
        } else {
            addHint = "No http or https links found"
        }
        linkFieldFocused = true
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

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Text("\(queue.activeCount) of \(maxConcurrent) downloading")
                .font(.callout)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                queue.pauseAll()
            } label: {
                Label("Pause", systemImage: "pause.fill")
            }
            .help("Pause running and pending downloads")
            .disabled(!queue.hasPausable)

            Button {
                queue.resumeAll()
            } label: {
                Label("Resume", systemImage: "play.fill")
            }
            .help("Resume paused downloads")
            .disabled(!queue.hasPaused)

            Menu {
                Button("Clear Finished") { queue.clearCompleted() }
                    .disabled(!queue.hasCompleted)
                Button("Clear All…") { confirmClearAll = true }
                    .disabled(queue.items.isEmpty)
            } label: {
                Label("Clear", systemImage: "trash")
            }
            .help("Clear finished or all items")

            Button {
                openWindow(id: WindowID.sites)
            } label: {
                Label("Sites", systemImage: "globe")
            }
            .help("How each site is handled")
        }
    }
}
