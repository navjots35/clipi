import SwiftUI
import AppKit

struct ClipboardRowView: View {
    let index: Int        // visible-list index (0-based, top of the visible list)
    let item: ClipboardItem
    let isSelected: Bool

    @State private var isHovering: Bool = false

    var body: some View {
        HStack(spacing: 10) {
            TypeIconView(contentType: item.contentType)

            VStack(alignment: .leading, spacing: 1) {
                titleLine
                    .lineLimit(1)
                    .truncationMode(.tail)

                HStack(spacing: 5) {
                    AppChipView(bundleID: item.sourceBundleID)
                        .frame(width: 11, height: 11)
                    Text(subtitle)
                        .lineLimit(1)
                }
                .font(.system(size: 11))
                .foregroundStyle(isSelected ? Color.white.opacity(0.78) : Color.secondary)
            }

            Spacer(minLength: 6)

            if let badge = shortcutBadge {
                KeyCapView(text: badge, dark: isSelected)
                    .frame(minWidth: 22)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 44)
        .background(rowBackground)
        .padding(.horizontal, 6)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
    }

    @ViewBuilder
    private var titleLine: some View {
        switch item.contentType {
        case .color(let hex):
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Color(hex: hex) ?? .gray)
                    .frame(width: 10, height: 10)
                    .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Color.black.opacity(0.15), lineWidth: 0.5))
                Text(hex)
            }
            .font(titleFont)
            .foregroundStyle(isSelected ? Color.white : Color.primary)
        default:
            Text(item.previewTitle)
                .font(titleFont)
                .foregroundStyle(isSelected ? Color.white : Color.primary)
        }
    }

    private var titleFont: Font {
        item.isMonospaceContent
            ? .system(size: 12, weight: .medium, design: .monospaced)
            : .system(size: 13, weight: .medium)
    }

    /// "Safari · 2s ago" — concise, app-first, with a relative timestamp.
    private var subtitle: String {
        if let app = item.sourceAppName {
            return "\(app) · \(item.relativeTimeText)"
        }
        return item.relativeTimeText
    }

    /// "1" through "9" then "0" for the top-10 visible items. We show the plain
    /// digit because that's the keystroke that actually works — `⌘1`–`⌘9` is
    /// intercepted by the previously-active app's menu (Chrome/Finder tabs)
    /// before our local NSEvent monitor sees it. Plain digits are caught when
    /// the search field is empty.
    private var shortcutBadge: String? {
        switch index {
        case 0...8: return "\(index + 1)"
        case 9:     return "0"
        default:    return nil
        }
    }

    @ViewBuilder
    private var rowBackground: some View {
        if isSelected {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.accentColor)
                .shadow(color: Color.accentColor.opacity(0.25), radius: 2, x: 0, y: 1)
        } else if isHovering {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        } else {
            Color.clear
        }
    }
}

// MARK: – Type icon

/// Colored 28×28 rounded square with a white glyph, matching the design's
/// per-content-type icon palette. Each tint is a flat fill with a subtle inner
/// highlight so it reads as a stacked Material chiclet rather than a flat tag.
struct TypeIconView: View {
    let contentType: ContentType

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(fillColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.25), lineWidth: 0.5)
                )
                .overlay(
                    // Single bright top-edge highlight for the "lit from above" feel.
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(LinearGradient(
                            colors: [Color.white.opacity(0.35), .clear],
                            startPoint: .top, endPoint: .center
                        ), lineWidth: 0.5)
                )
            glyph
        }
        .frame(width: 28, height: 28)
    }

    private var fillColor: Color {
        switch contentType {
        case .text:     return Color(hex: "#0A84FF") ?? .blue
        case .link:     return Color(hex: "#5E5CE6") ?? .indigo
        case .code:     return Color(hex: "#1F2937") ?? .black
        case .color:    return .white   // the glyph layer paints the swatch
        case .image:    return Color(hex: "#34C759") ?? .green
        case .email:    return Color(hex: "#0A84FF") ?? .blue
        case .json:     return Color(hex: "#FF9500") ?? .orange
        case .phone:    return Color(hex: "#34C759") ?? .green
        case .file:     return Color(hex: "#5AC8FA") ?? .teal
        case .markdown: return Color(hex: "#111827") ?? .black
        case .other:    return Color(hex: "#8E8E93") ?? .gray
        }
    }

    @ViewBuilder
    private var glyph: some View {
        switch contentType {
        case .text:
            Text("Aa")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        case .link:
            Image(systemName: "link")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
        case .code:
            Image(systemName: "chevron.left.forwardslash.chevron.right")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
        case .color(let hex):
            // Inner swatch on a white tile so any color reads cleanly.
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.white)
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color(hex: hex) ?? .gray)
                    .frame(width: 18, height: 18)
                    .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.black.opacity(0.10), lineWidth: 0.5))
            }
            .frame(width: 28, height: 28)
        case .image:
            Image(systemName: "photo")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
        case .email:
            Image(systemName: "envelope.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
        case .json:
            Text("{ }")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        case .phone:
            Image(systemName: "phone.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
        case .file:
            Image(systemName: "doc.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
        case .markdown:
            Text("M↓")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        case .other:
            Image(systemName: "doc.richtext")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
        }
    }
}

// MARK: – App-source chip

/// Tiny rounded square showing the source app's icon. Falls back to a generic
/// dot when the bundle ID is unknown or its icon can't be resolved.
struct AppChipView: View {
    let bundleID: String?

    var body: some View {
        if let bundleID,
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .interpolation(.high)
                .scaledToFit()
        } else {
            RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                .fill(Color.secondary.opacity(0.4))
        }
    }
}

// MARK: – Key cap

/// Rounded pill that mimics the design's `.kbd` key-cap. Inverted (white-on-glass)
/// when on a selected accent-blue row.
struct KeyCapView: View {
    let text: String
    var dark: Bool = false

    var body: some View {
        // Precompute the ternary `Color` choices — inlining them as
        // `dark ? Color.white.opacity(...) : Color.black.opacity(...)`
        // inside the SwiftUI modifier chain blew up the type-checker
        // (>900ms per body call).
        let foreground: Color = dark ? Color.white.opacity(0.78) : Color.secondary
        let backgroundFill: Color = dark ? Color.white.opacity(0.10) : Color.black.opacity(0.06)
        let strokeColor: Color = dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06)

        return Text(text)
            .font(.system(size: 10.5, weight: .medium))
            .foregroundStyle(foreground)
            .padding(.horizontal, 4)
            .frame(minWidth: 16, minHeight: 16)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(backgroundFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(strokeColor, lineWidth: 0.5)
            )
    }
}

// MARK: – Color hex helper

extension Color {
    /// Build a Color from a `#RRGGBB` / `#RRGGBBAA` string. Returns nil for malformed input.
    init?(hex raw: String) {
        var s = raw
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6 || s.count == 8, let v = UInt64(s, radix: 16) else { return nil }
        let r, g, b, a: Double
        if s.count == 6 {
            r = Double((v >> 16) & 0xff) / 255
            g = Double((v >> 8)  & 0xff) / 255
            b = Double(v & 0xff) / 255
            a = 1.0
        } else {
            r = Double((v >> 24) & 0xff) / 255
            g = Double((v >> 16) & 0xff) / 255
            b = Double((v >> 8)  & 0xff) / 255
            a = Double(v & 0xff) / 255
        }
        self.init(red: r, green: g, blue: b, opacity: a)
    }
}

