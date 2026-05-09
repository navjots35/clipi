import AppKit
import ApplicationServices

enum CaretLocator {
    /// Returns the screen-coordinate frame of the focused text caret, in NSWindow space
    /// (origin at bottom-left of the primary display). Returns nil if Accessibility is
    /// not granted, no text element is focused, or the focused app refuses to report it.
    static func currentCaretFrame() -> NSRect? {
        guard AXIsProcessTrusted() else { return nil }

        let systemWide = AXUIElementCreateSystemWide()

        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
              let focused = focusedRef
        else { return nil }
        let element = focused as! AXUIElement

        var rangeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeRef) == .success,
              let range = rangeRef
        else { return nil }

        var boundsRef: CFTypeRef?
        let err = AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            range,
            &boundsRef
        )
        guard err == .success, let bv = boundsRef else { return nil }

        var axRect = CGRect.zero
        guard AXValueGetValue(bv as! AXValue, .cgRect, &axRect) else { return nil }

        // AX uses top-left origin on the primary display; NSWindow uses bottom-left.
        let primaryHeight = NSScreen.screens
            .first(where: { $0.frame.origin == .zero })?.frame.height
            ?? NSScreen.main?.frame.height
            ?? axRect.maxY
        let nsRect = NSRect(
            x: axRect.origin.x,
            y: primaryHeight - axRect.origin.y - axRect.height,
            width: max(axRect.width, 1),
            height: max(axRect.height, 1)
        )
        return nsRect
    }
}
