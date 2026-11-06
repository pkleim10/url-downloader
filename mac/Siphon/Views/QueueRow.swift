import AppKit
import SwiftUI

struct QueueRow: View {
    let item: QueueItem
    let queue: DownloadQueue

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.displayTitle)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                if item.title != nil {
                    Text(item.url)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                tags
                if showsProgress {
                    progress
                }
                if item.status == .failed, let reason = item.failReason {
                    Text(reason)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .help(reason)
                }
            }
            Spacer(minLength: 8)
            statusBadge
            if item.status == .completed, item.filePath != nil {
                Button {
                    revealFile()
                } label: {
                    Image(systemName: "magnifyingglass")
                }
                .buttonStyle(.borderless)
                .help("Show in Finder")
            }
            Button {
                queue.remove(item.id)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help("Remove from queue")
        }
        .padding(.vertical, 4)
        .contextMenu { contextMenu }
    }

    private var showsProgress: Bool {
        item.status == .downloading || (item.status == .paused && item.fraction != nil)
    }

    @ViewBuilder
    private var tags: some View {
        let parts = [
            item.siteName.map { "Site: \($0)" },
            item.prefix.isEmpty ? nil : "Prefix: \(item.prefix)",
        ].compactMap { $0 }
        if !parts.isEmpty {
            Text(parts.joined(separator: "  ·  "))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var progress: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let fraction = item.fraction {
                ProgressView(value: fraction)
            } else {
                ProgressView()
                    .progressViewStyle(.linear)
            }
            let detail = Formatters.progressDetail(for: item)
            Text(detail.isEmpty ? "Starting…" : detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    /// Clicking the badge does the obvious next thing, as on the web page.
    private var statusBadge: some View {
        Button(action: badgeAction) {
            Text(item.status.label)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .foregroundStyle(statusColor)
                .background(statusColor.opacity(0.15), in: Capsule())
        }
        .buttonStyle(.plain)
        .help(badgeHelp)
        .disabled(item.status == .completed)
    }

    private var statusColor: Color {
        switch item.status {
        case .pending: .secondary
        case .downloading: .blue
        case .paused: .orange
        case .failed: .red
        case .completed: .green
        }
    }

    private var badgeHelp: String {
        switch item.status {
        case .pending, .downloading: "Click to pause"
        case .paused: "Click to resume"
        case .failed: "Click to retry"
        case .completed: "Downloaded"
        }
    }

    private func badgeAction() {
        switch item.status {
        case .pending, .downloading: queue.pause(item.id)
        case .paused: queue.resume(item.id)
        case .failed: queue.retry(item.id)
        case .completed: break
        }
    }

    @ViewBuilder
    private var contextMenu: some View {
        switch item.status {
        case .pending, .downloading:
            Button("Pause") { queue.pause(item.id) }
        case .paused:
            Button("Resume") { queue.resume(item.id) }
        case .failed:
            Button("Retry") { queue.retry(item.id) }
        case .completed:
            Button("Show in Finder") { revealFile() }
                .disabled(item.filePath == nil)
        }
        Button("Copy Link") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(item.url, forType: .string)
        }
        Divider()
        Button("Remove", role: .destructive) { queue.remove(item.id) }
    }

    private func revealFile() {
        guard let path = item.filePath else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }
}
