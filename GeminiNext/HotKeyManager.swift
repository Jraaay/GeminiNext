import Cocoa
import Carbon

/// Global hotkey callback function, satisfies @convention(c) requirement
private func hotKeyHandler(nextHandler: EventHandlerCallRef?, event: EventRef?, userData: UnsafeMutableRawPointer?) -> OSStatus {
    DispatchQueue.main.async {
        HotKeyManager.shared.onHotKeyPressed()
    }
    return noErr
}

class HotKeyManager {
    static let shared = HotKeyManager()
    private var hotKeyRef: EventHotKeyRef?
    /// Event handler only needs to be installed once
    private var handlerInstalled = false
    
    private init() {}
    
    /// Register hotkey on first launch (called at app startup)
    func register() {
        installHandlerIfNeeded()
        registerCurrentPreset()
    }

    /// Re-register hotkey (called when settings change)
    func reRegister() {
        unregisterHotKey()
        registerCurrentPreset()
    }

    // MARK: - Private Methods

    /// Install Carbon event handler (only once)
    private func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetApplicationEventTarget(), hotKeyHandler, 1, &eventType, nil, nil)
        
        if status != noErr {
            print("Failed to install event handler: \(status)")
        } else {
            handlerInstalled = true
        }
    }

    /// Register hotkey based on current settings
    private func registerCurrentPreset() {
        let preset = SettingsManager.shared.hotKeyPreset
        let hotKeyID = EventHotKeyID(signature: OSType(0x53574654), id: 1)
        
        let regStatus = RegisterEventHotKey(
            preset.keyCode,
            preset.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        
        if regStatus != noErr {
            print("Failed to register hotkey: \(regStatus)")
        } else {
            print("Global hotkey \(preset.displayName) registered successfully")
        }
    }

    /// Unregister the current hotkey
    private func unregisterHotKey() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
    }
    
    func onHotKeyPressed() {
        // Check if there are any visible windows
        let hasVisibleWindow = NSApp.windows.contains { $0.isVisible } && NSApp.isActive

        if hasVisibleWindow {
            // If the app is in the foreground with visible windows, hide it
            NSApp.hide(nil)
        } else {
            // Otherwise (app in background, or foreground but window not visible), activate and show
            NSApp.activate(ignoringOtherApps: true)

            // Only activate the main window (delegate is AppDelegate), skip settings windows etc.
            for window in NSApp.windows where window.delegate is AppDelegate {
                window.makeKeyAndOrderFront(nil)
                window.orderFrontRegardless()
                // Ensure opacity is normal (prevent animation artifacts)
                window.alphaValue = 1.0
            }
        }
    }
}
