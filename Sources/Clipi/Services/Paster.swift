import AppKit
import UserNotifications

enum Paster {
    /// Convenience: write the item then trigger an auto-paste once the call returns
    /// to the main loop. Used by paths that don't need to coordinate with a window
    /// animation — just write and fire.
    static func paste(_ item: ClipboardItem, plain: Bool = false) {
        writePasteboard(item, plain: plain)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            triggerPaste()
        }
    }

    /// Phase 1 — writes the chosen item back to the system pasteboard.
    /// When `plain` is true and the item is text, only `public.utf8-plain-text` is
    /// written so the receiving app can't pull rich formatting off the pasteboard.
    /// Should be called *before* the panel begins closing so manual ⌘V always works
    /// even if auto-paste is later skipped (e.g., AX denied).
    static func writePasteboard(_ item: ClipboardItem, plain: Bool = false) {
        if plain, case .text(let s) = item.kind {
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(s, forType: .string)
        } else {
            item.snapshot.write(to: .general)
        }
    }

    /// Phase 2 — synthesizes ⌘V into the frontmost app, or shows a notification if
    /// Accessibility hasn't been granted yet. Call from the panel-close completion
    /// handler so the keystroke is dispatched *after* the panel has fully resigned
    /// key / been orderOut'd; otherwise the synthetic event can race with the
    /// closing window and miss the receiving app.
    static func triggerPaste() {
        if isAccessibilityTrusted() {
            postCommandV()
        } else {
            notify(title: "Copied to clipboard",
                   body: "Press ⌘V to paste. Grant Accessibility to enable auto-paste.")
        }
    }

    static func isAccessibilityTrusted(prompt: Bool = false) -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let opts: [String: Bool] = [key: prompt]
        return AXIsProcessTrustedWithOptions(opts as CFDictionary)
    }

    /// Opens System Settings → Privacy & Security → Accessibility.
    static func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    private static func postCommandV() {
        let src = CGEventSource(stateID: .combinedSessionState)
        let vKey: CGKeyCode = 0x09 // kVK_ANSI_V
        let down = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: true)
        let up = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        let tap: CGEventTapLocation = .cghidEventTap
        down?.post(tap: tap)
        up?.post(tap: tap)
    }

    private static func notify(title: String, body: String) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert]) { _, _ in }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        center.add(req)
    }
}
