import SwiftUI

/// Shared look, modeled on the web page: soft page background, white rounded cards, blue accent.
enum Theme {
    static let accent = Color(red: 0, green: 0.478, blue: 1) // #007AFF
    static let pageBackground = Color(nsColor: .underPageBackgroundColor)
    static let cardBackground = Color(nsColor: .textBackgroundColor)
    static let cardBorder = Color.primary.opacity(0.08)
    static let cornerRadius: CGFloat = 12
}

struct CardModifier: ViewModifier {
    var padding: CGFloat = 16
    var radius: CGFloat = Theme.cornerRadius

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Theme.cardBorder))
            .shadow(color: .black.opacity(0.07), radius: 8, y: 2)
    }
}

extension View {
    func card(padding: CGFloat = 16, radius: CGFloat = Theme.cornerRadius) -> some View {
        modifier(CardModifier(padding: padding, radius: radius))
    }
}

/// Large text field with a 2-pt border that turns blue when focused, like the web inputs.
struct FieldBox<Content: View>: View {
    let focused: Bool
    @ViewBuilder let content: Content

    var body: some View {
        content
            .textFieldStyle(.plain)
            .font(.system(size: 14))
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(focused ? Theme.accent : Color.primary.opacity(0.15), lineWidth: 2)
            )
            .animation(.easeOut(duration: 0.15), value: focused)
    }
}

/// Full-width blue button that darkens on hover, like the web page's Download button.
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(fill(pressed: configuration.isPressed), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.99 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.15), value: hovering)
    }

    private func fill(pressed: Bool) -> Color {
        guard isEnabled else { return Color.gray.opacity(0.4) }
        return pressed || hovering ? Color(red: 0, green: 0.337, blue: 0.8) : Theme.accent // #0056CC
    }
}

struct FieldLabel: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.secondary)
    }
}

/// Filled blue capsule, used for the queue count.
struct CountPill: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .monospacedDigit()
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .background(Theme.accent, in: Capsule())
    }
}

/// Slim rounded progress bar; nil fraction shows an animated sweep.
struct SlimProgressBar: View {
    let fraction: Double?
    var tint: Color = Theme.accent

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                if let fraction {
                    Capsule()
                        .fill(tint)
                        .frame(width: max(6, geo.size.width * min(max(fraction, 0), 1)))
                        .animation(.easeOut(duration: 0.3), value: fraction)
                } else {
                    IndeterminateSweep(tint: tint, width: geo.size.width)
                }
            }
        }
        .frame(height: 6)
        .clipShape(Capsule())
    }
}

private struct IndeterminateSweep: View {
    let tint: Color
    let width: CGFloat
    @State private var phase = false

    var body: some View {
        Capsule()
            .fill(tint.opacity(0.8))
            .frame(width: width * 0.3)
            .offset(x: phase ? width : -width * 0.3)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: false)) { phase = true }
            }
    }
}

extension DownloadStatus {
    var tint: Color {
        switch self {
        case .pending: .gray
        case .downloading: Theme.accent
        case .paused: .orange
        case .failed: .red
        case .completed: .green
        }
    }

    var symbol: String {
        switch self {
        case .pending: "clock"
        case .downloading: "arrow.down"
        case .paused: "pause.fill"
        case .failed: "exclamationmark"
        case .completed: "checkmark"
        }
    }
}
