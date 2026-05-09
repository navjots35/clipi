import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = ClipboardStore()
    private var watcher: PasteboardWatcher!
    private var hotkey: HotkeyManager!
    private var statusItem: StatusItemController!
    private var panel: PanelController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        watcher = PasteboardWatcher(store: store)
        panel = PanelController(store: store)
        statusItem = StatusItemController(store: store,
                                          onShow: { [weak self] in self?.panel.toggle() },
                                          onSettings: { [weak self] in self?.openSettings() })
        hotkey = HotkeyManager()

        watcher.start()
        statusItem.install()
        hotkey.register { [weak self] in self?.panel.toggle() }

        // Trigger the system Accessibility prompt on first launch. Needed for both
        // auto-paste (CGEvent ⌘V) and caret-aware panel positioning. Subsequent
        // launches with permission granted are silent.
        _ = Paster.isAccessibilityTrusted(prompt: true)

        // First-run welcome card. Only shows once per machine; users can re-open
        // it from the status-item menu.
        OnboardingWindowController.shared.showIfNeeded()
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotkey?.unregister()
        watcher?.stop()
    }

    func openSettings() {
        SettingsWindowController.shared.show(store: store)
    }

    func showOnboarding() {
        OnboardingWindowController.shared.showAnyway()
    }
}

@main
struct ClipiApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    var body: some Scene {
        Settings { EmptyView() }
    }
}
