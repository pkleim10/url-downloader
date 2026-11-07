import AppKit
import SwiftUI

/// The yt-dlp command and output for one item, updating live while it downloads.
struct LogView: View {
    let item: QueueItem
    let queue: DownloadQueue
    @Environment(\.dismiss) private var dismiss

    private var lines: [String] { queue.logs[item.id] ?? [] }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayTitle)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(item.url)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            ScrollViewReader { proxy in
                ScrollView([.vertical, .horizontal]) {
                    Text(lines.isEmpty ? "No output yet." : lines.joined(separator: "\n"))
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                    Color.clear.frame(height: 1).id("end")
                }
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.cardBorder))
                .onAppear { proxy.scrollTo("end", anchor: .bottomLeading) }
                .onChange(of: lines.count) { proxy.scrollTo("end", anchor: .bottomLeading) }
            }

            HStack {
                Text("Kept until you quit Siphon or remove the item.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Copy Log", action: copy)
                    .disabled(lines.isEmpty)
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(minWidth: 640, idealWidth: 760, minHeight: 360, idealHeight: 480)
    }

    private func copy() {
        var text = "Siphon log\nURL: \(item.url)\nStatus: \(item.status.label)"
        if let reason = item.failReason { text += "\nError: \(reason)" }
        text += "\n\n" + lines.joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
