import AppKit
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

/// Hosts the SwiftUI settings pane in a regular `NSWindow`. Activates the app
/// (`.regular` policy) while open so the window can take focus and key events,
/// then drops back to `.accessory` on close so clipi stays out of the Dock.
///
/// Lifecycle has a single one-way drain. Any close trigger — red traffic-light
/// button, ⌘W, programmatic — eventually causes AppKit to fire
/// `willCloseNotification`. The observer below handles cleanup *only*; it
/// never re-closes the window. (Earlier version was a delegate that called
/// `window.close()` from `windowWillClose`, which re-entered AppKit's close
/// path and recursed until the stack overflowed — see crash 2026-05-09.)
final class SettingsWindowController {
    static let shared = SettingsWindowController()
    private var window: NSWindow?
    private var closeObserver: NSObjectProtocol?

    func show(store: ClipboardStore) {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let view = SettingsRoot(store: store, onClose: { [weak self] in self?.dismiss() })
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 720, height: 520)

        let w = NSWindow(contentRect: host.frame,
                         styleMask: [.titled, .closable, .fullSizeContentView],
                         backing: .buffered,
                         defer: false)
        w.title = "clipi Settings"
        w.titlebarAppearsTransparent = false
        w.contentView = host
        w.center()
        w.makeKeyAndOrderFront(nil)

        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: w,
            queue: .main
        ) { [weak self] _ in self?.cleanupAfterClose() }

        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        self.window = w
    }

    /// Programmatic close. The window itself initiates the close; the
    /// `willCloseNotification` observer above drains the rest of the state.
    private func dismiss() {
        window?.close()
    }

    /// State drain only — never call `close()` from here. Runs once per show()
    /// regardless of which path triggered the close.
    private func cleanupAfterClose() {
        if let observer = closeObserver {
            NotificationCenter.default.removeObserver(observer)
            closeObserver = nil
        }
        window = nil
        NSApp.setActivationPolicy(.accessory)
    }
}

// MARK: – SwiftUI root

private struct SettingsRoot: View {
    @ObservedObject var store: ClipboardStore
    @ObservedObject private var settings = AppSettings.shared
    @State private var section: Section = .general
    let onClose: () -> Void

    enum Section: String, CaseIterable, Identifiable {
        case general, history, rules, shortcuts, appearance, about
        var id: String { rawValue }
        var label: String {
            switch self {
            case .general:    return "General"
            case .history:    return "History"
            case .rules:      return "Per-app rules"
            case .shortcuts:  return "Shortcuts"
            case .appearance: return "Appearance"
            case .about:      return "About"
            }
        }
        var icon: String {
            switch self {
            case .general:    return "gearshape.fill"
            case .history:    return "clock.fill"
            case .rules:      return "shield.lefthalf.filled"
            case .shortcuts:  return "keyboard.fill"
            case .appearance: return "paintpalette.fill"
            case .about:      return "info.circle.fill"
            }
        }
        var tint: Color {
            switch self {
            case .general:    return Color(hex: "#8E8E93") ?? .gray
            case .history:    return Color(hex: "#0A84FF") ?? .blue
            case .rules:      return Color(hex: "#34C759") ?? .green
            case .shortcuts:  return Color(hex: "#FF9500") ?? .orange
            case .appearance: return Color(hex: "#AF52DE") ?? .purple
            case .about:      return Color(hex: "#5E5CE6") ?? .indigo
            }
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 188)
                .background(Color.primary.opacity(0.015))
            Divider()
            ScrollView {
                pane
                    .padding(.horizontal, 24)
                    .padding(.vertical, 20)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var sidebar: some View {
        VStack(spacing: 1) {
            ForEach(Section.allCases) { s in
                sidebarRow(s)
            }
            Spacer()
        }
        .padding(8)
    }

    private func sidebarRow(_ s: Section) -> some View {
        HStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(s.tint)
                    .frame(width: 18, height: 18)
                Image(systemName: s.icon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white)
            }
            Text(s.label)
                .font(.system(size: 13))
                .foregroundStyle(.primary)
            Spacer()
        }
        .padding(.horizontal, 8)
        .frame(height: 28)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(section == s ? Color.primary.opacity(0.07) : .clear)
        )
        .contentShape(Rectangle())
        .onTapGesture { section = s }
    }

    @ViewBuilder
    private var pane: some View {
        switch section {
        case .general:    GeneralPane(settings: settings)
        case .history:    HistoryPane(settings: settings, store: store)
        case .rules:      RulesPane(settings: settings)
        case .shortcuts:  ShortcutsPane()
        case .appearance: AppearancePane()
        case .about:      AboutPane()
        }
    }
}

// MARK: – General

private struct GeneralPane: View {
    @ObservedObject var settings: AppSettings
    /// Mirrors `SMAppService.mainApp.status` on appear so the toggle reflects
    /// reality even if Login Items was edited from System Settings between launches.
    @State private var launchAtLogin: Bool = SMAppService.mainApp.status == .enabled
    @AppStorage("ShowCopyNotifications") private var showCopyNotifications: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            settingsSection("Startup") {
                ToggleRow(label: "Launch clipi at login",
                          sub: "Adds clipi to System Settings → General → Login Items",
                          value: launchAtLoginBinding)
                Divider()
                ToggleRow(label: "Show notifications when copying",
                          sub: "Posts a banner each time clipi captures a new clipboard item",
                          value: $showCopyNotifications, last: true)
            }
        }
        .onAppear {
            // Re-sync in case the user removed clipi from Login Items elsewhere.
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    /// Toggling routes through `SMAppService.mainApp`; failures roll the UI
    /// state back so we don't claim success when the system rejected the change.
    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { launchAtLogin },
            set: { newValue in
                let old = launchAtLogin
                launchAtLogin = newValue
                do {
                    if newValue {
                        try SMAppService.mainApp.register()
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                } catch {
                    NSLog("clipi: Launch-at-login toggle failed: \(error.localizedDescription)")
                    launchAtLogin = old
                }
            }
        )
    }
}

// MARK: – History

private struct HistoryPane: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var store: ClipboardStore

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            settingsSection("Storage") {
                StepperRow(label: "Items kept in history",
                           sub: "Older items are removed automatically",
                           value: Binding(
                               get: { store.maxItems },
                               set: { store.maxItems = max(1, min(50, $0)) }
                           ),
                           range: 1...50,
                           unit: "items",
                           last: true)
            }
            settingsSection("Privacy") {
                ToggleRow(label: "Skip items copied from password fields",
                          sub: "Uses Accessibility to detect AXSecureTextField focus",
                          value: $settings.excludeSecureFields,
                          last: true)
            }
            Button(role: .destructive) { store.clear() } label: {
                Text("Clear history…").font(.system(size: 12, weight: .medium))
            }
        }
    }
}

// MARK: – Rules (the security-critical pane)

private struct RulesPane: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Decide which apps clipi watches. Excluded apps are never recorded — even if they copy a password, token, or sensitive note.")
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 0) {
                ForEach(settings.rules) { rule in
                    RuleRow(rule: rule)
                    if rule.id != settings.rules.last?.id { Divider() }
                }
            }
            .background(Color(NSColor.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
            )

            Button(action: addAppRule) {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                    Text("Add app rule…")
                }
                .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    private func addAppRule() {
        let panel = NSOpenPanel()
        panel.title = "Choose an app"
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.begin { response in
            guard response == .OK,
                  let url = panel.url,
                  let bundle = Bundle(url: url),
                  let bundleID = bundle.bundleIdentifier else { return }
            let name = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                    ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
                    ?? url.deletingPathExtension().lastPathComponent
            DispatchQueue.main.async {
                AppSettings.shared.setRule(AppRule(bundleID: bundleID, appName: name, mode: .exclude))
            }
        }
    }
}

private struct RuleRow: View {
    let rule: AppRule
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        HStack(spacing: 10) {
            AppChipView(bundleID: rule.bundleID).frame(width: 20, height: 20)
            Text(rule.appName).font(.system(size: 13))
            Spacer()
            Picker("", selection: Binding(
                get: { rule.mode },
                set: { newMode in
                    var updated = rule
                    updated.mode = newMode
                    settings.setRule(updated)
                }
            )) {
                ForEach(AppRule.Mode.allCases, id: \.self) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 160)

            Button(role: .destructive) {
                settings.removeRule(bundleID: rule.bundleID)
            } label: {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

// MARK: – Shortcuts

private struct ShortcutsPane: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            settingsSection("Global hotkeys") {
                ShortcutRow(label: "Open clipboard", keys: ["⌥", "⌘", "V"])
                Divider()
                ShortcutRow(label: "Paste as plain text",
                            sub: "Modifier + Return inside the panel",
                            keys: ["⌘", "↵"], last: true)
            }
            Text("Custom shortcut recording is not yet wired up — the global hotkey is currently fixed at ⌥⌘V to avoid conflicting with macOS's ⌘⇧V (Paste and Match Style).")
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct ShortcutRow: View {
    let label: String
    var sub: String? = nil
    let keys: [String]
    var last: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.system(size: 13))
                if let sub {
                    Text(sub).font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            Spacer()
            HStack(spacing: 3) { ForEach(keys, id: \.self) { KeyCapView(text: $0) } }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

// MARK: – Appearance (display-only for now)

private struct AppearancePane: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Appearance options from the design (theme / accent / translucency / corner radius) aren't wired up yet — clipi follows the system appearance and uses the design's defaults.")
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: – About

private struct AboutPane: View {
    private var version: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "Version \(short) (\(build))"
    }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(LinearGradient(
                        colors: [Color(hex: "#0A84FF") ?? .blue, Color(hex: "#5E5CE6") ?? .indigo],
                        startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 56, height: 56)
                Image(systemName: "doc.on.clipboard")
                    .font(.system(size: 26, weight: .light))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("clipi").font(.system(size: 20, weight: .bold, design: .rounded))
                Text(version).font(.system(size: 12)).foregroundStyle(.secondary)
                Text("A keyboard-first clipboard for macOS. History persists locally and per-app rules keep passwords out of capture.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 6)
            }
            Spacer()
        }
    }
}

// MARK: – Shared row primitives

private func settingsSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 8) {
        Text(title.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(.tertiary)
        VStack(spacing: 0) {
            content()
        }
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
    }
}

private struct ToggleRow: View {
    let label: String
    var sub: String? = nil
    @Binding var value: Bool
    var last: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.system(size: 13))
                if let sub {
                    Text(sub).font(.system(size: 11)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer()
            Toggle("", isOn: $value).labelsHidden().toggleStyle(.switch)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

private struct StepperRow: View {
    let label: String
    var sub: String? = nil
    @Binding var value: Int
    let range: ClosedRange<Int>
    let unit: String
    var last: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.system(size: 13))
                if let sub {
                    Text(sub).font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            Spacer()
            HStack(spacing: 4) {
                Text("\(value) \(unit)")
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(.secondary)
                Stepper("", value: $value, in: range).labelsHidden()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}
