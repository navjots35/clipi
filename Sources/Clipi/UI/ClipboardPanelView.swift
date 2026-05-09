import SwiftUI
import AppKit
import ApplicationServices

struct ClipboardPanelView: View {
    @ObservedObject var store: ClipboardStore
    /// `plain == true` means strip rich types so the receiving app sees plain text only.
    let onPick: (ClipboardItem, _ plain: Bool) -> Void
    let onDismiss: () -> Void

    @State private var query: String = ""
    @State private var selection: Int = 0
    @State private var axGranted: Bool = AXIsProcessTrusted()
    @State private var keyMonitor: Any?
    @FocusState private var searchFocused: Bool

    private var filteredItems: [ClipboardItem] {
        guard !query.isEmpty else { return store.items }
        let q = query.lowercased()
        return store.items.filter { $0.searchHaystack.contains(q) }
    }

    var body: some View {
        VStack(spacing: 0) {
            if !axGranted { axBanner }
            searchField
            Divider().opacity(0.4)
            content
            Divider().opacity(0.4)
            footer
        }
        .background(panelChrome)
        .onAppear {
            searchFocused = true
            installKeyMonitor()
            // Re-check AX on each open so the banner disappears once granted without a relaunch.
            axGranted = AXIsProcessTrusted()
        }
        .onDisappear { removeKeyMonitor() }
        .onChange(of: filteredItems.count) { _ in
            // Keep selection in range when the filter changes.
            if selection >= filteredItems.count { selection = max(0, filteredItems.count - 1) }
        }
    }

    // MARK: – Chrome

    /// Vibrant Tahoe-style glass: regular material with a fine inner highlight and
    /// a soft drop shadow. The 16-px radius matches the design's `--radius` default.
    private var panelChrome: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.regularMaterial)
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.55), lineWidth: 0.5)
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.black.opacity(0.10), lineWidth: 0.5)
                .blendMode(.multiply)
        }
        .compositingGroup()
        .shadow(color: Color.black.opacity(0.35), radius: 30, x: 0, y: 18)
        .shadow(color: Color.black.opacity(0.18), radius: 8, x: 0, y: 4)
    }

    // MARK: – AX banner

    private var axBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "lock.shield")
                .font(.system(size: 13))
                .foregroundStyle(.yellow)
            VStack(alignment: .leading, spacing: 1) {
                Text("Auto-paste & smart positioning need Accessibility").font(.system(size: 12, weight: .medium))
                Text("Open Settings, enable clipi, then quit and relaunch.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button("Open Settings") { Paster.openAccessibilitySettings() }
                .buttonStyle(.borderless)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.accentColor)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Color.yellow.opacity(0.10))
    }

    // MARK: – Search

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            TextField("Search clipboard…", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .focused($searchFocused)
                // Belt-and-braces: the NSEvent local monitor should already catch
                // Return, but if SwiftUI's TextField swallows it first this fallback
                // still triggers the paste action. Bare Enter only — modifier-laden
                // returns (⌘↵ for plain) still go through the local monitor.
                .onSubmit { pickSelected(plain: false) }
            KeyCapView(text: "esc")
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }

    // MARK: – Content

    @ViewBuilder
    private var content: some View {
        if store.items.isEmpty {
            emptyState
        } else if filteredItems.isEmpty {
            noResultsState
        } else {
            list
        }
    }

    private var sectionLabel: some View {
        HStack {
            Text("RECENT")
                .font(.system(size: 10.5, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(.tertiary)
            Spacer()
            Text("\(store.items.count) item\(store.items.count == 1 ? "" : "s") · 24h")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(Color.primary.opacity(0.30))
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    private var list: some View {
        VStack(spacing: 0) {
            sectionLabel
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 1) {
                        // Identify rows by their integer position only. Mixing the
                        // UUID-based `id: \.element.id` with a child `.id(idx)` made
                        // SwiftUI race between two identities and stale-render when
                        // the store reordered, pinning every row to the first item.
                        ForEach(Array(filteredItems.enumerated()), id: \.offset) { idx, item in
                            ClipboardRowView(index: idx, item: item, isSelected: idx == selection)
                                .onTapGesture { onPick(item, /* plain */ false) }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .onChange(of: selection) { newValue in
                    withAnimation(.easeOut(duration: 0.10)) { proxy.scrollTo(newValue, anchor: .center) }
                }
            }
        }
    }

    /// First-run / no-content state: tinted clipboard glyph, helper text, and a
    /// keycap row showing the summon shortcut.
    private var emptyState: some View {
        VStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(LinearGradient(
                        colors: [.white, Color(hex: "#EEF0F5") ?? .gray],
                        startPoint: .top, endPoint: .bottom))
                    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.black.opacity(0.08), lineWidth: 0.5))
                    .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 4)
                    .frame(width: 56, height: 56)
                Image(systemName: "doc.on.clipboard")
                    .font(.system(size: 26, weight: .light))
                    .foregroundStyle(Color.accentColor)
            }
            Text("Your clipboard is empty")
                .font(.system(size: 15, weight: .semibold))
            Text("Copy anything anywhere and clipi will keep the last 10 items here. Press ⌥⌘V to summon this panel under your cursor.")
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(nil)
                .frame(maxWidth: 260)
            HStack(spacing: 6) {
                KeyCapView(text: "⌥")
                KeyCapView(text: "⌘")
                KeyCapView(text: "V")
            }
            .padding(.top, 4)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 48)
        .frame(maxWidth: .infinity)
    }

    private var noResultsState: some View {
        VStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(.tertiary)
            Text("No matches for \"\(query)\"")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 140)
        .padding(20)
    }

    // MARK: – Footer

    /// Hint bar at the bottom with kbd-styled keys, mirroring the design layout:
    /// `↑↓ Move · ↵ Paste · ⌘↵ Plain · ……… · ⌘,`
    private var footer: some View {
        HStack(spacing: 14) {
            footerHint(keys: ["↑", "↓"], label: "Move")
            footerHint(keys: ["↵"], label: "Paste")
            footerHint(keys: ["⌘", "↵"], label: "Plain")
            Spacer(minLength: 8)
            HStack(spacing: 3) {
                KeyCapView(text: "⌘")
                KeyCapView(text: ",")
            }
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Color.primary.opacity(0.02))
    }

    private func footerHint(keys: [String], label: String) -> some View {
        HStack(spacing: 4) {
            HStack(spacing: 2) {
                ForEach(keys, id: \.self) { KeyCapView(text: $0) }
            }
            Text(label)
        }
    }

    // MARK: – Key handling

    /// Intercepts ↑↓⏎esc and ⌘digits before they reach the search TextField.
    /// Cmd+Return takes the "plain text" branch; bare Return takes the formatted one.
    /// Anything else (alphanumerics, backspace) flows through to the field.
    private func installKeyMonitor() {
        if keyMonitor != nil { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            switch event.keyCode {
            case 126: move(-1); return nil          // ↑
            case 125: move(1); return nil           // ↓
            case 36, 76:                             // return / numpad enter
                pickSelected(plain: event.modifierFlags.contains(.command))
                return nil
            case 53:                                 // esc
                if !query.isEmpty { query = ""; return nil }
                onDismiss(); return nil
            default: break
            }
            if event.modifierFlags.contains(.command),
               let chars = event.charactersIgnoringModifiers {
                // ⌘, opens Settings (matches the footer affordance and the standard
                // macOS menu shortcut). The panel closes first so the Settings
                // window can take focus cleanly.
                if chars == "," {
                    onDismiss()
                    DispatchQueue.main.async {
                        (NSApp.delegate as? AppDelegate)?.openSettings()
                    }
                    return nil
                }
                if let scalar = chars.unicodeScalars.first,
                   let digit = Int(String(scalar)),
                   (0...9).contains(digit) {
                    pickAt(digit == 0 ? 9 : digit - 1)
                    return nil
                }
            }
            return event
        }
    }

    private func removeKeyMonitor() {
        if let monitor = keyMonitor { NSEvent.removeMonitor(monitor) }
        keyMonitor = nil
    }

    private func move(_ delta: Int) {
        guard !filteredItems.isEmpty else { return }
        selection = max(0, min(selection + delta, filteredItems.count - 1))
    }

    private func pickSelected(plain: Bool) {
        guard filteredItems.indices.contains(selection) else { return }
        onPick(filteredItems[selection], plain)
    }

    private func pickAt(_ idx: Int) {
        guard filteredItems.indices.contains(idx) else { return }
        onPick(filteredItems[idx], false)
    }
}
