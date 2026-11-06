import AppKit
import SwiftUI

struct QueueRow: View {
    let item: QueueItem
    let queue: DownloadQueue

    @State private var hovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            statusIcon
            VStack(alignment: .leading, spacing: 5) {
                Text(item.displayTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                if item.title != nil {
                    Text(item.url)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                tags
                if showsProgress {
                    progress
                        .padding(.top, 2)
                }
                if item.status == .failed, let reason = item.failReason {
                    Text(reason)
                        .font(.system(size: 11))
                        .foregroundStyle(.red)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .help(reason)
                }
            }
            Spacer(minLength: 8)
            HStack(spacing: 6) {
                statusBadge
                if item.status == .completed, item.filePath != nil {
                    iconButton("magnifyingglass", help: "Show in Finder", action: revealFile)
                }
                iconButton("xmark", help: "Remove from queue") { queue.remove(item.id) }
                    .opacity(hovering ? 1 : 0.55)
            }
        }
        .card(padding: 12, radius: 10)
        .onHover { hovering = $0 }
        .contextMenu { contextMenu }
    }

    private var showsProgress: Bool {
        item.status == .downloading || (item.status == .paused && item.fraction != nil)
    }

    private var statusIcon: some View {
        Image(systemName: item.status.symbol)
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(item.status.tint)
            .frame(width: 30, height: 30)
            .background(item.status.tint.opacity(0.14), in: Circle())
            .symbolEffect(.pulse, isActive: item.status == .downloading)
    }

    @ViewBuilder
    private var tags: some View {
        if item.siteName != nil || !item.prefix.isEmpty {
            HStack(spacing: 6) {
                if let site = item.siteName { tag(site, systemImage: "globe") }
                if !item.prefix.isEmpty { tag(item.prefix, systemImage: "textformat") }
            }
        }
    }

    private func tag(_ text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Color.primary.opacity(0.06), in: Capsule())
    }

    private var progress: some View {
        VStack(alignment: .leading, spacing: 4) {
            SlimProgressBar(
                fraction: item.fraction,
                tint: item.status == .paused ? DownloadStatus.paused.tint : Theme.accent
            )
            HStack {
                let amount = Formatters.progressAmount(for: item)
                Text(amount.isEmpty ? "Starting…" : amount)
                Spacer()
                Text(Formatters.progressRemaining(for: item))
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .monospacedDigit()
        }
    }

    private func iconButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)
                .background(Color.primary.opacity(0.06), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    /// Clicking the badge does the obvious next thing, as on the web page.
    private var statusBadge: some View {
        Button(action: badgeAction) {
            Text(item.status.label)
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .foregroundStyle(item.status.tint)
                .background(item.status.tint.opacity(0.15), in: Capsule())
        }
        .buttonStyle(.plain)
        .help(badgeHelp)
        .disabled(item.status == .completed)
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
