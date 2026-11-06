import AppKit
import SwiftUI

/// Finished downloads, newest first, searchable by title, link, or site.
struct HistoryView: View {
    let queue: DownloadQueue
    @State private var search = ""
    @State private var confirmClear = false

    private var history: DownloadHistory { queue.history }

    private var filtered: [HistoryEntry] {
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return history.entries }
        return history.entries.filter { entry in
            [entry.title, entry.url, entry.siteName].contains { $0?.localizedCaseInsensitiveContains(query) == true }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("History")
                    .font(.system(size: 15, weight: .semibold))
                CountPill(text: "\(history.entries.count)")
                Spacer()
                Button("Clear History…") { confirmClear = true }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(history.entries.isEmpty)
            }
            .padding(.horizontal, 4)

            if !AppSettings.keepHistory {
                Text("History is turned off in Settings, so new downloads aren't recorded.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }

            if history.entries.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "clock")
                        .font(.system(size: 28, weight: .light))
                        .foregroundStyle(.tertiary)
                    Text("No finished downloads yet")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .card()
            } else {
                List(filtered) { entry in
                    HistoryRow(entry: entry, queue: queue)
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 3, leading: 0, bottom: 3, trailing: 0))
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .overlay {
                    if filtered.isEmpty {
                        Text("No matches for \"\(search)\"")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(16)
        .frame(minWidth: 520, minHeight: 360)
        .background(Theme.pageBackground)
        .searchable(text: $search, placement: .toolbar, prompt: "Search titles, links, sites")
        .confirmationDialog("Clear all download history?", isPresented: $confirmClear) {
            Button("Clear History", role: .destructive) { history.clear() }
        } message: {
            Text("Downloaded files stay where they are. Links you download again won't be flagged as duplicates.")
        }
    }
}

private struct HistoryRow: View {
    let entry: HistoryEntry
    let queue: DownloadQueue

    var body: some View {
        let exists = entry.fileExists
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: exists ? "checkmark" : "questionmark")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(exists ? Color.green : Color.secondary)
                .frame(width: 28, height: 28)
                .background((exists ? Color.green : Color.secondary).opacity(0.14), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(entry.displayTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(spacing: 6) {
                    Text(entry.downloadedAt.formatted(date: .abbreviated, time: .shortened))
                    if let size = entry.sizeBytes { Text("·"); Text(Formatters.bytes(size)) }
                    if let site = entry.siteName { Text("·"); Text(site) }
                    if !exists { Text("·"); Text("File moved or deleted").foregroundStyle(.orange) }
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            Spacer(minLength: 8)
            Button("Download Again") { queue.downloadAgain(entry) }
                .buttonStyle(SecondaryButtonStyle())
            Button {
                revealFile()
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .background(Color.primary.opacity(0.06), in: Circle())
            }
            .buttonStyle(.plain)
            .help("Show in Finder")
            .disabled(!exists)
        }
        .card(padding: 10, radius: 10)
        .contextMenu {
            Button("Show in Finder", action: revealFile).disabled(!exists)
            Button("Download Again") { queue.downloadAgain(entry) }
            Button("Copy Link") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(entry.url, forType: .string)
            }
            Divider()
            Button("Remove from History", role: .destructive) { queue.history.remove(entry.id) }
        }
        .help(entry.url)
    }

    private func revealFile() {
        guard let path = entry.filePath else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }
}
