import AppKit
import SwiftUI

/// Read-only view of the persistent `sites.json`: how each site is handled and when it was last tested.
struct SitesView: View {
    let queue: DownloadQueue
    @State private var query = ""

    var body: some View {
        let shown = Self.visible(queue.sites.sites, matching: query)
        VStack(alignment: .leading, spacing: 0) {
            if queue.sites.sites.isEmpty {
                ContentUnavailableView(
                    "No site configurations",
                    systemImage: "globe",
                    description: Text("Sites without an entry use yt-dlp's built-in support.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if shown.isEmpty {
                ContentUnavailableView.search(text: query)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        if query.isEmpty {
                            ForEach(SiteLearner.sharedPlayers(in: queue.sites.sites)) { shared in
                                SharedPlayerNote(shared: shared)
                            }
                        }
                        ForEach(shown) { site in
                            SiteRow(site: site, pluginSource: queue.sites.pluginSource(for: site))
                        }
                    }
                    .padding(12)
                }
                .background(Theme.pageBackground)
            }
            Divider()
            footer
        }
        .searchable(text: $query, placement: .toolbar, prompt: "Search sites")
        .frame(minWidth: 480, minHeight: 320)
    }

    /// "recipe (smartScan)" for recipes built on a built-in, "recipe (custom)" otherwise.
    static func methodLabel(for site: SiteConfig) -> String {
        guard let recipe = site.recipe else { return site.method }
        return "\(site.method) (\(recipe.base ?? "custom"))"
    }

    /// Sites sorted by name, filtered to those whose name, domains, method or status contain every word of `query`.
    static func visible(_ sites: [SiteConfig], matching query: String) -> [SiteConfig] {
        let words = query.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        return sites
            .filter { site in
                let text = ([site.name, site.method, site.status] + site.match).joined(separator: " ").lowercased()
                return words.allSatisfy(text.contains)
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("Sites Siphon hasn't seen are tested on first download and added here.")
                Spacer()
                Button("Show in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([queue.sitesFolder.appendingPathComponent("sites.json")])
                }
                .controlSize(.small)
            }
            Text("Sites: \(queue.sitesFolder.path)")
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

private struct SharedPlayerNote: View {
    let shared: SiteLearner.SharedPlayer

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "rectangle.3.group")
                .foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text("Shared player: \(shared.host)")
                    .font(.callout.weight(.semibold))
                Text("\(shared.siteNames.formatted(.list(type: .and))) embed the same player. It may deserve its own built-in recipe.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .card(padding: 12, radius: 10)
    }
}

private struct SiteRow: View {
    let site: SiteConfig
    let pluginSource: String?

    @State private var expanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 6) {
                detail("Matches", site.match.joined(separator: ", "))
                detail("Method", SitesView.methodLabel(for: site))
                if let recipe = site.recipe {
                    let lines = recipe.details
                    if lines.isEmpty, recipe.base != nil {
                        detail("Recipe", "the built-in as is")
                    }
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                        detail(line.label, line.value)
                    }
                }
                detail("yt-dlp options", site.ytDlpArgs.isEmpty ? "None" : site.ytDlpArgs.joined(separator: " "))
                if let plugin = site.plugin { detail("Plugin", plugin) }
                if let lastTested = site.lastTested { detail("Last tested", lastTested) }
                if let testResult = site.testResult { detail("Test result", testResult) }
                if let notes = site.notes { detail("Notes", notes) }
                if let example = site.exampleUrl { detail("Example", example) }
            }
            .padding(.top, 8)
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
                if site.isLearned {
                    Text("Learned")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Theme.accent.opacity(0.12), in: Capsule())
                }
                Spacer()
                Text(site.status.capitalized)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(statusColor)
            }
            .contentShape(Rectangle())
            .onTapGesture { withAnimation(.snappy) { expanded.toggle() } }
        }
        .card(padding: 12, radius: 10)
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
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 100, alignment: .trailing)
            Text(value)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.callout)
    }
}
