import AppKit
import SwiftUI

/// First-run welcome card. Shows once, then sets the `OnboardingCompleted`
/// UserDefaults flag so subsequent launches go straight to the menu-bar app.
final class OnboardingWindowController {
    static let shared = OnboardingWindowController()
    private var window: NSWindow?
    private static let completedKey = "OnboardingCompleted"

    func showIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: Self.completedKey) else { return }
        showAnyway()
    }

    func showAnyway() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let view = OnboardingView(onDismiss: { [weak self] in self?.dismiss() })
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 540, height: 420)

        let w = NSWindow(contentRect: host.frame,
                         styleMask: [.titled, .fullSizeContentView, .closable],
                         backing: .buffered,
                         defer: false)
        w.title = "Welcome to clipi"
        w.titleVisibility = .hidden
        w.titlebarAppearsTransparent = true
        w.isMovableByWindowBackground = true
        w.contentView = host
        w.center()
        w.makeKeyAndOrderFront(nil)

        // Catch traffic-light close so we still drop activation policy back to
        // accessory and mark onboarding completed.
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification,
                                               object: w,
                                               queue: .main) { [weak self] _ in
            self?.cleanupAfterClose()
        }

        // Clipi runs as `.accessory` (no Dock icon). For an interactive window we
        // briefly elevate to `.regular` so the user can actually focus and click
        // the buttons; we drop back to `.accessory` on dismiss.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        self.window = w
    }

    private func dismiss() {
        // Just trigger close — `cleanupAfterClose` runs from willCloseNotification.
        window?.close()
    }

    private func cleanupAfterClose() {
        UserDefaults.standard.set(true, forKey: Self.completedKey)
        window = nil
        NSApp.setActivationPolicy(.accessory)
    }
}

private struct OnboardingView: View {
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            steps.padding(.top, 4)
            actions.padding(.top, 8)
            pagination
        }
        .padding(28)
        .frame(width: 540, alignment: .leading)
    }

    private var header: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(LinearGradient(
                        colors: [Color(hex: "#0A84FF") ?? .blue, Color(hex: "#5E5CE6") ?? .indigo],
                        startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 48, height: 48)
                    .shadow(color: (Color(hex: "#0A84FF") ?? .blue).opacity(0.4), radius: 12, x: 0, y: 6)
                Image(systemName: "doc.on.clipboard")
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Welcome to clipi")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                Text("A keyboard-first clipboard that lives where your cursor is.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var steps: some View {
        VStack(alignment: .leading, spacing: 14) {
            step(1, "Press to summon",
                 "Hit ⌥⌘V anywhere. clipi opens right under your cursor.")
            step(2, "Pick with one key",
                 "Use ↑↓ or just press 1–9. Hit ↵ to paste — ⌘↵ for plain text.")
            step(3, "Stays out of trouble",
                 "1Password, banking sites, and password fields are excluded by default.")
        }
    }

    private func step(_ n: Int, _ title: String, _ body: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 24, height: 24)
                Text("\(n)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.accentColor)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13.5, weight: .semibold))
                Text(body).font(.system(size: 12.5)).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var actions: some View {
        HStack(spacing: 10) {
            Button(action: onDismiss) {
                Text("Try it now — Press ⌥⌘V")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Button(action: onDismiss) {
                Text("Skip")
                    .font(.system(size: 13, weight: .medium))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
    }

    private var pagination: some View {
        HStack(spacing: 6) {
            Spacer()
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(i == 0 ? Color.accentColor : Color.secondary.opacity(0.3))
                    .frame(width: 6, height: 6)
            }
            Spacer()
        }
        .padding(.top, 4)
    }
}
