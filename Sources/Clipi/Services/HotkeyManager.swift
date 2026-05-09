import AppKit
import Carbon.HIToolbox

final class HotkeyManager {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var callback: (() -> Void)?

    /// Registers ⌥⌘V as a system-wide hotkey. Calls `onPress` on the main thread when fired.
    /// ⌥⌘V (not ⌘⇧V) because ⌘⇧V is macOS's "Paste and Match Style" — when the panel
    /// opens with the search field focused, repeated/leaked ⌘⇧V keystrokes pasted
    /// the user's current clipboard straight into our TextField.
    func register(onPress: @escaping () -> Void) {
        self.callback = onPress

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, eventRef, userData in
            guard let userData, let eventRef else { return noErr }
            var hkID = EventHotKeyID()
            let status = GetEventParameter(eventRef,
                                           EventParamName(kEventParamDirectObject),
                                           EventParamType(typeEventHotKeyID),
                                           nil,
                                           MemoryLayout<EventHotKeyID>.size,
                                           nil,
                                           &hkID)
            guard status == noErr else { return status }
            let mgr = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async { mgr.callback?() }
            return noErr
        }, 1, &eventType, selfPtr, &eventHandler)

        let hkID = EventHotKeyID(signature: OSType(0x434C4250) /* 'CLBP' */, id: 1)
        // ⌥⌘V — kVK_ANSI_V is 0x09; modifiers OR'd.
        let modifiers: UInt32 = UInt32(cmdKey | optionKey)
        RegisterEventHotKey(UInt32(kVK_ANSI_V), modifiers, hkID, GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
        hotKeyRef = nil
        eventHandler = nil
    }

    deinit { unregister() }
}
