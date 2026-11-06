import SwiftUI

/// Read-only view of `sites/sites.json`: how each site is handled and when it was last tested.
struct SitesView: View {
    let queue: DownloadQueue

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if queue.sites.sites.isEmpty {
                ContentUnavailableView(
                    "No site configurations",
                    systemImage: "globe",
                    description: Text("Sites without an entry use yt-dlp's built-in support.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(queue.sites.sites) { site in
                    SiteRow(site: site, pluginSource: queue.sites.pluginSource(for: site))
                }
                .listStyle(.inset)
            }
            Divider()
            footer
        }
        .frame(minWidth: 480, minHeight: 320)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Sites without an entry use yt-dlp's built-in support.")
            if let ytDlp = queue.ytDlpPath {
                Text("yt-dlp: \(ytDlp.path)")
            }
            if let plugins = queue.sites.pluginDirectory {
                Text("Plugins: \(plugins.path)")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .textSelection(.enabled)
        .padding(12)
    }
}

private struct SiteRow: View {
    let site: SiteConfig
    let pluginSource: String?

    var body: some View {
        DisclosureGroup {
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 6) {
                detail("Matches", site.match.joined(separator: ", "))
                detail("Method", site.method)
                detail("yt-dlp options", site.ytDlpArgs.isEmpty ? "None" : site.ytDlpArgs.joined(separator: " "))
                if let plugin = site.plugin { detail("Plugin", plugin) }
                if let lastTested = site.lastTested { detail("Last tested", lastTested) }
                if let testResult = site.testResult { detail("Test result", testResult) }
                if let notes = site.notes { detail("Notes", notes) }
                if let example = site.exampleUrl { detail("Example", example) }
            }
            .padding(.vertical, 6)
            if let pluginSource {
                ScrollView(.horizontal) {
                    Text(pluginSource)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(8)
                }
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
            }
        } label: {
            HStack {
                Text(site.name).font(.body.weight(.medium))
                Spacer()
                Text(site.status.capitalized)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(statusColor)
            }
        }
    }

    private var statusColor: Color {
        switch site.status {
        case "working": .green
        case "broken": .red
        case "unsupported": .orange
        default: .secondary
        }
    }

    private func detail(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
                .gridColumnAlignment(.trailing)
            Text(value)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.callout)
    }
}
