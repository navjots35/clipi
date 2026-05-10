import AppKit
import SwiftUI

/// NSPanel subclass that can take key status without activating its app.
/// Required so the search field can become first responder when the panel opens
/// while the user's previous app stays frontmost (paste-back works against it).
final class ClipboardPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class PanelController {
    private var panel: ClipboardPanel?
    private let store: ClipboardStore
    private var resignKeyObserver: NSObjectProtocol?
    /// True from the moment `close()` starts an animation until orderOut completes.
    /// Used to drop reentrant close calls — the local NSEvent monitor and SwiftUI's
    /// TextField `.onSubmit` can both fire for the same Enter, and without this we'd
    /// post ⌘V twice and paste the chosen item into the destination twice.
    private var closing = false
    private static let panelSize = NSSize(width: 380, height: 520)
    private static let caretGap: CGFloat = 8

    init(store: ClipboardStore) {
        self.store = store
    }

    func toggle() {
        if let panel, panel.isVisible {
            close()
        } else {
            open()
        }
    }

    func open() {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        positionForPaste(panel)
        animateIn(panel)
        installResignKeyObserver(for: panel)
    }

    /// Closes the panel. The optional `completion` runs on the main thread *after*
    /// the close animation finishes and the panel has been `orderOut`'d — required
    /// for callers that need to dispatch synthetic keystrokes into the previously
    /// active app without racing the closing window.
    func close(completion: (() -> Void)? = nil) {
        guard let panel else { completion?(); return }
        if closing { return }   // a paste is already in flight; drop the duplicate
        closing = true
        if let token = resignKeyObserver {
            NotificationCenter.default.removeObserver(token)
            resignKeyObserver = nil
        }
        animateOut(panel) { [weak self] in
            self?.closing = false
            completion?()
        }
    }

    // MARK: – Window construction

    private func makePanel() -> ClipboardPanel {
        let view = ClipboardPanelView(
            store: store,
            onPick: { [weak self] item, plain in
                // Write the pasteboard *before* the panel begins closing so the
                // user can manually ⌘V even if AX-driven auto-paste is denied.
                Paster.writePasteboard(item, plain: plain)
                self?.close { Paster.triggerPaste() }
            },
            onDismiss: { [weak self] in self?.close() }
        )
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(origin: .zero, size: Self.panelSize)
        host.wantsLayer = true
        // Anchor at center so scale animation grows outward instead of from a corner.
        if let layer = host.layer {
            layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            layer.position = CGPoint(x: host.frame.midX, y: host.frame.midY)
        }

        let p = ClipboardPanel(
            contentRect: NSRect(origin: .zero, size: Self.panelSize),
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        p.isMovableByWindowBackground = true
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = true
        p.animationBehavior = .none // we own the animation timing
        p.contentView = host
        return p
    }

    // MARK: – Positioning

    /// Three-tier positioning, most-specific to least-specific:
    ///   1. Text caret (via Accessibility) — accurate but unavailable in many
    ///      Electron/browser contexts that don't implement
    ///      `kAXBoundsForRangeParameterizedAttribute`.
    ///   2. Mouse cursor — what most users mean when they say "pops up under
    ///      your cursor" (Windows-style). Always available.
    ///   3. Spotlight-style center — only hit when the mouse is somehow off
    ///      every connected screen.
    private func positionForPaste(_ panel: ClipboardPanel) {
        let size = panel.frame.size

        // Tier 1: text caret.
        if let caret = CaretLocator.currentCaretFrame(),
           let screen = screen(containing: NSPoint(x: caret.midX, y: caret.midY)) ?? NSScreen.main {
            // Below the caret with a small gap; if it would clip off-screen, place above.
            var origin = NSPoint(x: caret.origin.x, y: caret.origin.y - size.height - Self.caretGap)
            if origin.y < screen.visibleFrame.minY + 8 {
                origin.y = caret.origin.y + caret.height + Self.caretGap
            }
            panel.setFrameOrigin(clamp(origin, size: size, in: screen.visibleFrame))
            return
        }

        // Tier 2: mouse cursor. Place the panel below-and-slightly-right of the
        // pointer so the cursor lands on the search field (where you'd start
        // typing immediately) rather than on a row.
        let mouse = NSEvent.mouseLocation
        if let mouseScreen = screen(containing: mouse) {
            let origin = NSPoint(x: mouse.x - 12, y: mouse.y - size.height - Self.caretGap)
            panel.setFrameOrigin(clamp(origin, size: size, in: mouseScreen.visibleFrame))
            return
        }

        // Tier 3: Spotlight-style center on the active screen.
        let active = activeScreen()
        let visible = active.visibleFrame
        let x = visible.midX - size.width / 2
        let y = visible.maxY - visible.height * 0.38 - size.height / 2
        panel.setFrameOrigin(clamp(NSPoint(x: x, y: y), size: size, in: visible))
    }

    /// Best guess at the screen the user is currently working on:
    /// the one containing the focused window if AX reports it, else the one with
    /// the mouse, else the primary.
    private func activeScreen() -> NSScreen {
        let mouse = NSEvent.mouseLocation
        return screen(containing: mouse) ?? NSScreen.main ?? NSScreen.screens.first!
    }

    private func screen(containing point: NSPoint) -> NSScreen? {
        NSScreen.screens.first(where: { $0.frame.contains(point) })
    }

    private func clamp(_ p: NSPoint, size: NSSize, in visible: NSRect) -> NSPoint {
        var origin = p
        origin.x = max(visible.minX + 8, min(origin.x, visible.maxX - size.width - 8))
        origin.y = max(visible.minY + 8, min(origin.y, visible.maxY - size.height - 8))
        return origin
    }

    // MARK: – Animation

    private func animateIn(_ panel: ClipboardPanel) {
        guard let host = panel.contentView, let layer = host.layer else {
            panel.alphaValue = 1
            panel.makeKeyAndOrderFront(nil)
            return
        }

        panel.alphaValue = 0
        layer.transform = CATransform3DMakeScale(0.96, 0.96, 1)
        panel.makeKeyAndOrderFront(nil)

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.14
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            ctx.allowsImplicitAnimation = true
            panel.animator().alphaValue = 1
            layer.transform = CATransform3DIdentity
        }
    }

    private func animateOut(_ panel: ClipboardPanel, completion: (() -> Void)? = nil) {
        guard panel.isVisible else { completion?(); return }
        let layer = panel.contentView?.layer
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.10
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            ctx.allowsImplicitAnimation = true
            panel.animator().alphaValue = 0
            layer?.transform = CATransform3DMakeScale(0.97, 0.97, 1)
        }, completionHandler: {
            panel.orderOut(nil)
            layer?.transform = CATransform3DIdentity
            // Give the WindowServer one tick to swing keyboard focus back to the
            // previously active app before any synthetic keystrokes are dispatched.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
                completion?()
            }
        })
    }

    // MARK: – Click-away via key-resignation

    private func installResignKeyObserver(for panel: ClipboardPanel) {
        if resignKeyObserver != nil { return }
        resignKeyObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            self?.close()
        }
    }
}
