import AppKit
import SwiftUI

struct ContentView: View {
    let queue: DownloadQueue

    @Environment(\.openWindow) private var openWindow
    @AppStorage(SettingsKey.destination) private var destinationPath = ""
    @AppStorage(SettingsKey.maxConcurrent) private var maxConcurrent = AppSettings.defaultMaxConcurrent
    @AppStorage(SettingsKey.hideInactive) private var hideInactive = false
    @State private var linkText = ""
    @State private var prefix = ""
    @State private var addHint: String?
    @State private var confirmClearAll = false
    @FocusState private var focusedField: Field?

    private enum Field { case links, prefix }

    var body: some View {
        VStack(spacing: 16) {
            addCard
            if queue.ytDlpPath == nil {
                missingYtDlpBanner
            }
            UpdateBanner(queue: queue)
            queueSection
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.pageBackground)
        .frame(minWidth: 580, minHeight: 560)
        .toolbar { toolbarContent }
        .dropDestination(for: URL.self) { urls, _ in
            queue.add(text: urls.map(\.absoluteString).joined(separator: "\n"))
        }
        .confirmationDialog("Remove every item from the queue?", isPresented: $confirmClearAll) {
            Button("Clear All", role: .destructive) { queue.clearAll() }
        } message: {
            Text("Running downloads stop. Files already downloaded stay where they are.")
        }
        .onAppear { focusedField = .links }
    }

    // MARK: - Add card

    private var addCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 34, height: 34)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Siphon")
                        .font(.system(size: 20, weight: .bold))
                    Text("Paste links or drop them on this window")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 5) {
                FieldLabel("Links")
                FieldBox(focused: focusedField == .links) {
                    TextField("Paste one or more URLs", text: $linkText, axis: .vertical)
                        .lineLimit(1...4)
                        .focused($focusedField, equals: .links)
                        .onSubmit(addLinks)
                }
            }

            HStack(alignment: .bottom, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    FieldLabel("Filename prefix")
                    FieldBox(focused: focusedField == .prefix) {
                        TextField("Optional", text: $prefix)
                            .focused($focusedField, equals: .prefix)
                            .onSubmit(addLinks)
                    }
                }
                VStack(alignment: .leading, spacing: 5) {
                    FieldLabel("Save to")
                    Button(action: chooseDestination) {
                        FieldBox(focused: false) {
                            HStack(spacing: 6) {
                                Image(systemName: "folder.fill")
                                    .foregroundStyle(Theme.accent)
                                Text(destinationName)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Spacer(minLength: 4)
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Save to \(AppSettings.destination)")
                }
            }

            Button(action: addLinks) {
                Label("Add to Queue", systemImage: "arrow.down.circle.fill")
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(linkText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            if let addHint {
                Text(addHint)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .transition(.opacity)
            }
        }
        .card(padding: 20)
    }

    // MARK: - Queue

    private var queueSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text("Queue")
                            .font(.system(size: 15, weight: .semibold))
                        CountPill(text: "\(queue.items.count)")
                    }
                    Text("\(queue.activeCount) of \(maxConcurrent) downloading"
                         + (hideInactive && hiddenCount > 0 ? " · \(hiddenCount) hidden" : ""))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Spacer()
                queueActions
            }
            .padding(.horizontal, 4)

            if queue.items.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "tray")
                        .font(.system(size: 28, weight: .light))
                        .foregroundStyle(.tertiary)
                    Text("No downloads yet")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .card()
                .padding(.bottom, 20)
            } else if visibleItems.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "eye.slash")
                        .font(.system(size: 28, weight: .light))
                        .foregroundStyle(.tertiary)
                    Text("Every item is failed or paused")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .card()
                .padding(.bottom, 20)
            } else {
                let visible = visibleItems
                List {
                    ForEach(visible) { item in
                        QueueRow(item: item, queue: queue)
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                    }
                    .onMove { queue.move(fromOffsets: $0, toOffset: $1, within: visible) }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .contentMargins(.bottom, 16, for: .scrollContent)
                .animation(.snappy, value: visible.map(\.id))
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var visibleItems: [QueueItem] {
        hideInactive ? queue.items.filter { !DownloadQueue.isInactive($0) } : queue.items
    }

    private var hiddenCount: Int {
        queue.items.filter(DownloadQueue.isInactive).count
    }

    private var queueActions: some View {
        HStack(spacing: 6) {
            Toggle(isOn: $hideInactive) {
                Text("Hide Failed & Paused")
                    .font(.system(size: 12))
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            .help("Leave failed and paused downloads out of the list")
            .padding(.trailing, 6)

            Button {
                queue.pauseAll()
            } label: {
                Label("Pause All", systemImage: "pause.fill")
            }
            .help("Pause running and pending downloads")
            .disabled(!queue.hasPausable)

            Button {
                queue.resumeAll()
            } label: {
                Label("Resume All", systemImage: "play.fill")
            }
            .help("Resume paused downloads")
            .disabled(!queue.hasPaused)

            Button {
                queue.clearCompleted()
            } label: {
                Label("Clear Completed", systemImage: "checkmark.circle")
            }
            .help("Remove finished downloads from the queue; the files stay")
            .disabled(!queue.hasCompleted)
        }
        .buttonStyle(SecondaryButtonStyle())
        .labelStyle(.titleAndIcon)
    }

    private var destinationName: String {
        let path = destinationPath.isEmpty ? AppSettings.defaultDestination : destinationPath
        return FileManager.default.displayName(atPath: path)
    }

    private var missingYtDlpBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text("yt-dlp isn't installed. Install it with Homebrew: brew install yt-dlp")
            Spacer()
            Button("Check Again") { queue.reloadSites() }
        }
        .font(.callout)
        .padding(12)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.orange.opacity(0.3)))
    }

    private func addLinks() {
        let added = queue.add(text: linkText, prefix: prefix, destination: AppSettings.destination)
        if added > 0 {
            linkText = ""
            addHint = added == 1 ? "Added 1 link" : "Added \(added) links"
            let held = queue.lastAddHeldDuplicates
            if held > 0 {
                addHint! += held == 1 ? ". 1 was downloaded before and is paused" : ". \(held) were downloaded before and are paused"
            }
        } else {
            addHint = "No http or https links found"
        }
        focusedField = .links
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
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                confirmClearAll = true
            } label: {
                Label("Clear All", systemImage: "trash")
            }
            .help("Remove every item from the queue")
            .disabled(queue.items.isEmpty)

            Button {
                openWindow(id: WindowID.history)
            } label: {
                Label("History", systemImage: "clock.arrow.circlepath")
            }
            .help("Finished downloads")

            Button {
                openWindow(id: WindowID.sites)
            } label: {
                Label("Sites", systemImage: "globe")
            }
            .help("How each site is handled")
        }
    }
}
