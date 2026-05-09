import AppKit
import ApplicationServices

/// Asks Accessibility whether the focused UI element of the current frontmost app
/// is a secure text field — i.e., a password input. clipi uses this as the last
/// line of defense for capturing browser/banking-site password fields, since
/// those apps generally don't mark concealed copies via `org.nspasteboard`.
enum SecureFieldDetector {
    /// True when the frontmost app's focused element has role `AXSecureTextField`.
    /// Returns false on any error or when AX permission isn't granted — fail open
    /// so missing AX never silently breaks normal copy capture for the user.
    static func isCurrentFieldSecure() -> Bool {
        guard AXIsProcessTrusted() else { return false }
        guard let app = NSWorkspace.shared.frontmostApplication else { return false }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)

        var focused: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(appElement,
                                                   kAXFocusedUIElementAttribute as CFString,
                                                   &focused)
        guard status == .success, let focused else { return false }
        let element = focused as! AXUIElement

        var role: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element,
                                            kAXRoleAttribute as CFString,
                                            &role) == .success,
              let roleString = role as? String
        else { return false }

        // `kAXSecureTextFieldRole` isn't bridged into Swift; the role value is a
        // stable string constant ("AXSecureTextField") so we compare directly.
        return roleString == "AXSecureTextField"
    }
}
