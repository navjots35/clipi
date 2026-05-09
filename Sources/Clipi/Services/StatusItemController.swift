import AppKit

final class StatusItemController: NSObject {
    private var statusItem: NSStatusItem?
    private let store: ClipboardStore
    private let onShow: () -> Void
    private let onSettings: () -> Void

    init(store: ClipboardStore,
         onShow: @escaping () -> Void,
         onSettings: @escaping () -> Void) {
        self.store = store
        self.onShow = onShow
        self.onSettings = onSettings
        super.init()
    }

    func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "clipi")
            button.image?.isTemplate = true
        }

        let menu = NSMenu()
        menu.addItem(withTitle: "Show clipi  ⌥⌘V", action: #selector(showPanel), keyEquivalent: "")
            .target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
            .target = self
        menu.addItem(withTitle: "Welcome…", action: #selector(showOnboarding), keyEquivalent: "")
            .target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Clear History", action: #selector(clearHistory), keyEquivalent: "")
            .target = self
        menu.addItem(withTitle: "Open Accessibility Settings…", action: #selector(openAccessibility), keyEquivalent: "")
            .target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit clipi", action: #selector(quit), keyEquivalent: "q")
            .target = self
        item.menu = menu
        self.statusItem = item
    }

    @objc private func showPanel() { onShow() }
    @objc private func showSettings() { onSettings() }
    @objc private func showOnboarding() { OnboardingWindowController.shared.showAnyway() }
    @objc private func clearHistory() { store.clear() }
    @objc private func openAccessibility() { Paster.openAccessibilitySettings() }
    @objc private func quit() { NSApp.terminate(nil) }
}
