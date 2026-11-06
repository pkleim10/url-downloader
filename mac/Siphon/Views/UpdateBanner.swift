import SwiftUI

/// Offers a yt-dlp update when one is known to be available, or when downloads are failing
/// with an old yt-dlp, then offers to retry the failed items.
struct UpdateBanner: View {
    let queue: DownloadQueue
    @State private var dismissed = false

    private var updater: YtDlpUpdater { queue.updater }

    private var shouldShow: Bool {
        guard !dismissed, queue.ytDlpPath != nil else { return false }
        switch updater.phase {
        case .updating, .updated, .failed: return true
        default: return updater.updateAvailable || (queue.hasFailed && updater.isStale)
        }
    }

    var body: some View {
        content
            .onChange(of: updater.phase) { dismissed = false }
    }

    @ViewBuilder
    private var content: some View {
        if shouldShow {
            HStack(spacing: 10) {
                icon
                Text(message)
                    .font(.system(size: 12))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                actions
                Button {
                    dismissed = true
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Dismiss")
                .disabled(updater.phase == .updating)
            }
            .padding(12)
            .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(tint.opacity(0.3)))
        }
    }

    @ViewBuilder
    private var icon: some View {
        if updater.phase == .updating {
            ProgressView().controlSize(.small)
        } else {
            Image(systemName: iconName).foregroundStyle(tint)
        }
    }

    private var iconName: String {
        switch updater.phase {
        case .updated: "checkmark.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        default: "arrow.down.circle.fill"
        }
    }

    private var tint: Color {
        switch updater.phase {
        case .updated: .green
        case .failed: .orange
        default: Theme.accent
        }
    }

    private var message: String {
        let installed = updater.installedVersion ?? "unknown"
        switch updater.phase {
        case .updating:
            return "Updating yt-dlp…"
        case .updated(let version):
            return queue.hasFailed
                ? "yt-dlp updated to \(version). Failed downloads may work now."
                : "yt-dlp updated to \(version)."
        case .failed(let reason):
            return "yt-dlp update failed: \(reason)"
        default:
            if updater.updateAvailable, let latest = updater.latestVersion {
                return "yt-dlp \(latest) is available (you have \(installed))."
            }
            let age = updater.ageInDays.map { " is \($0) days old" } ?? " is out of date"
            return "yt-dlp \(installed)\(age). Updating often fixes failed downloads."
        }
    }

    @ViewBuilder
    private var actions: some View {
        switch updater.phase {
        case .updating:
            EmptyView()
        case .updated:
            if queue.hasFailed {
                Button("Retry Failed") {
                    queue.retryAllFailed()
                    dismissed = true
                }
                .buttonStyle(SecondaryButtonStyle())
            }
        default:
            Button("Update yt-dlp") {
                Task { await queue.updateYtDlp() }
            }
            .buttonStyle(SecondaryButtonStyle())
        }
    }
}
