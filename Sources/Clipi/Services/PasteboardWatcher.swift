import AppKit
import UserNotifications

final class PasteboardWatcher {
    private let store: ClipboardStore
    private let settings: AppSettings
    private let pasteboard: NSPasteboard
    private var lastChangeCount: Int
    private var timer: Timer?

    init(store: ClipboardStore,
         settings: AppSettings = .shared,
         pasteboard: NSPasteboard = .general) {
        self.store = store
        self.settings = settings
        self.pasteboard = pasteboard
        self.lastChangeCount = pasteboard.changeCount
    }

    func start() {
        guard timer == nil else { return }
        let t = Timer(timeInterval: 0.5, target: self, selector: #selector(tick), userInfo: nil, repeats: true)
        RunLoop.main.add(t, forMode: .common)
        self.timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    @objc private func tick() {
        let current = pasteboard.changeCount
        guard current != lastChangeCount else { return }
        lastChangeCount = current

        guard let pbItems = pasteboard.pasteboardItems, let first = pbItems.first else { return }

        // Capture the source app at the moment we observe the pasteboard change.
        // Skip our own writes (auto-paste back) so we don't claim authorship.
        let frontmost = NSWorkspace.shared.frontmostApplication
        let bundleID = frontmost?.bundleIdentifier
        let appName = frontmost?.localizedName
        if bundleID == Bundle.main.bundleIdentifier {
            // Our own paste-back wrote this; the dedupe will collapse it anyway,
            // but skip the new-item bookkeeping for clarity.
            return
        }

        // Per-app rule. Defaults exclude well-known password managers; users
        // can edit the list in Settings.
        let mode = settings.mode(for: bundleID)
        if mode == .exclude { return }

        // Layered defense for browser / banking-site password fields, which
        // generally don't mark concealed copies via `org.nspasteboard`.
        if settings.excludeSecureFields, SecureFieldDetector.isCurrentFieldSecure() { return }

        let plainOnly = (mode == .plain)

        // Finder copies a multi-file selection as N pasteboard items, each with .fileURL.
        // Collapse into one entry so the panel shows "3 files: …" instead of three rows.
        // Plain-mode rules forbid file copies entirely, so this branch is skipped in
        // that case and we fall through to the text-only path.
        if !plainOnly,
           pbItems.count > 1,
           pbItems.allSatisfy({ $0.types.contains(.fileURL) }) {
            let urls: [URL] = pbItems.compactMap {
                guard let s = $0.string(forType: .fileURL) else { return nil }
                return URL(string: s)
            }
            if urls.count == pbItems.count, let snap = PasteboardSnapshot(item: first) {
                store.add(ClipboardItem(snapshot: snap, kind: .fileURLs(urls),
                                        addedAt: Date(), sourceBundleID: bundleID, sourceAppName: appName))
                return
            }
        }

        if let item = ClipboardItem.make(from: first,
                                         bundleID: bundleID,
                                         appName: appName,
                                         plainOnly: plainOnly) {
            store.add(item)
            postCaptureNotificationIfEnabled(for: item)
        }
    }

    /// Posts a banner each time clipi captures a new clipboard item — but only
    /// when the user has explicitly opted in via Settings → General. The flag
    /// lives in `UserDefaults` (mirrored by `@AppStorage` in the toggle UI).
    /// Notifications still require user permission via `UNUserNotificationCenter`;
    /// the system will silently drop posts if denied.
    private func postCaptureNotificationIfEnabled(for item: ClipboardItem) {
        guard UserDefaults.standard.bool(forKey: "ShowCopyNotifications") else { return }
        let content = UNMutableNotificationContent()
        content.title = "clipi captured"
        content.body = item.previewTitle
        if let app = item.sourceAppName { content.subtitle = "from \(app)" }

        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert]) { _, _ in }
        let req = UNNotificationRequest(identifier: UUID().uuidString,
                                        content: content,
                                        trigger: nil)
        center.add(req)
    }
}
