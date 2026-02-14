import Cocoa
import Carbon

/// Hotkey ID constants for distinguishing multiple global hotkeys
private enum HotKeyIDs {
    static let showHide: UInt32 = 1
    static let newChat: UInt32 = 2
    static let signature: OSType = OSType(0x53574654)
}

/// Global hotkey callback function conforming to @convention(c)
private func hotKeyHandler(nextHandler: EventHandlerCallRef?, event: EventRef?, userData: UnsafeMutableRawPointer?) -> OSStatus {
    guard let event = event else { return OSStatus(eventNotHandledErr) }

    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )

    guard status == noErr else { return status }

    DispatchQueue.main.async {
        switch hotKeyID.id {
        case HotKeyIDs.showHide:
            HotKeyManager.shared.onHotKeyPressed()
        case HotKeyIDs.newChat:
            HotKeyManager.shared.onNewChatHotKeyPressed()
        default:
            break
        }
    }
    return noErr
}

class HotKeyManager {
    static let shared = HotKeyManager()
    private var hotKeyRef: EventHotKeyRef?
    private var newChatHotKeyRef: EventHotKeyRef?
    /// Event handler only needs to be installed once
    private var handlerInstalled = false
    /// Prevent repeated triggers during animation
    private var isAnimating = false

    /// Animation duration (seconds), no more than 200ms
    private let animationDuration: TimeInterval = 0.15
    
    private init() {}
    
    /// Register hotkey on initial launch
    func register() {
        installHandlerIfNeeded()
        registerCurrentHotKey()
        registerNewChatHotKey()
    }

    /// Re-register hotkey (called when settings change)
    /// - Parameter enabled: when false, only unregister without re-registering (recording mode)
    func reRegister(enabled: Bool = true) {
        unregisterHotKey()
        unregisterNewChatHotKey()
        if enabled {
            registerCurrentHotKey()
            registerNewChatHotKey()
        }
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

    /// Register show/hide hotkey based on current settings
    private func registerCurrentHotKey() {
        guard let hotKey = SettingsManager.shared.customHotKey else {
            print("Global hotkey disabled, skipping registration")
            return
        }
        let hotKeyID = EventHotKeyID(signature: HotKeyIDs.signature, id: HotKeyIDs.showHide)
        
        let regStatus = RegisterEventHotKey(
            hotKey.keyCode,
            hotKey.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        
        if regStatus != noErr {
            print("Failed to register hotkey: \(regStatus)")
        } else {
            print("Global hotkey \(hotKey.displayName) registered successfully")
        }
    }

    /// Register new-chat hotkey based on current settings
    private func registerNewChatHotKey() {
        guard let hotKey = SettingsManager.shared.newChatHotKey else {
            print("New-chat hotkey disabled, skipping registration")
            return
        }
        let hotKeyID = EventHotKeyID(signature: HotKeyIDs.signature, id: HotKeyIDs.newChat)

        let regStatus = RegisterEventHotKey(
            hotKey.keyCode,
            hotKey.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &newChatHotKeyRef
        )

        if regStatus != noErr {
            print("Failed to register new-chat hotkey: \(regStatus)")
        } else {
            print("New-chat hotkey \(hotKey.displayName) registered successfully")
        }
    }

    /// Unregister the show/hide hotkey
    private func unregisterHotKey() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
    }

    /// Unregister the new-chat hotkey
    private func unregisterNewChatHotKey() {
        if let ref = newChatHotKeyRef {
            UnregisterEventHotKey(ref)
            newChatHotKeyRef = nil
        }
    }
    
    func onHotKeyPressed() {
        // If animation is in progress, ignore this trigger
        guard !isAnimating else { return }

        // Check if there are any visible windows
        let hasVisibleWindow = NSApp.windows.contains { $0.isVisible } && NSApp.isActive

        if hasVisibleWindow {
            // App is in the foreground with visible windows → hide
            hideWithAnimation()
        } else {
            // Otherwise (background / window not visible) → activate and show
            showWithAnimation()
        }
    }

    /// Handle new-chat hotkey: activate window then send Cmd+Shift+O to the web page
    func onNewChatHotKeyPressed() {
        guard !isAnimating else { return }

        let hasVisibleWindow = NSApp.windows.contains { $0.isVisible } && NSApp.isActive

        if hasVisibleWindow {
            // Window is already visible, send the key event directly
            sendCmdShiftO()
        } else {
            // Activate and show window first, then send the key event
            showWithAnimation {
                // Delay slightly to ensure the window and WebView are fully ready
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    self.sendCmdShiftO()
                }
            }
        }
    }

    /// Send Cmd+Shift+O key event to the key window via CGEvent
    private func sendCmdShiftO() {
        guard let window = NSApp.keyWindow ?? NSApp.windows.first(where: { $0.isVisible && $0.canBecomeKey }) else { return }
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return }

        // kVK_ANSI_O = 0x1F
        let keyCode: CGKeyCode = CGKeyCode(kVK_ANSI_O)

        // keyDown with Cmd+Shift
        if let cgDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true) {
            cgDown.flags = [.maskCommand, .maskShift]
            if let nsDown = NSEvent(cgEvent: cgDown) {
                window.sendEvent(nsDown)
            }
        }

        // keyUp
        if let cgUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) {
            cgUp.flags = [.maskCommand, .maskShift]
            if let nsUp = NSEvent(cgEvent: cgUp) {
                window.sendEvent(nsUp)
            }
        }
    }

    // MARK: - Animation Methods

    /// Show window with fade-in animation
    /// - Parameter completion: optional callback after activation completes
    private func showWithAnimation(completion: (() -> Void)? = nil) {
        let useAnimation = SettingsManager.shared.windowAnimation

        NSApp.activate(ignoringOtherApps: true)

        for window in NSApp.windows where window.delegate is AppDelegate {
            if useAnimation {
                // Set fully transparent first, then fade in
                window.alphaValue = 0
            }
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()

            if useAnimation {
                isAnimating = true
                NSAnimationContext.runAnimationGroup({ context in
                    context.duration = animationDuration
                    context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    window.animator().alphaValue = 1.0
                }, completionHandler: { [weak self] in
                    self?.isAnimating = false
                    completion?()
                })
            } else {
                window.alphaValue = 1.0
                completion?()
            }
        }
    }

    /// Hide window with fade-out animation
    private func hideWithAnimation() {
        let useAnimation = SettingsManager.shared.windowAnimation

        if useAnimation {
            isAnimating = true
            // Perform fade-out animation on all main windows
            for window in NSApp.windows where window.delegate is AppDelegate {
                NSAnimationContext.runAnimationGroup({ context in
                    context.duration = animationDuration
                    context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                    window.animator().alphaValue = 0
                }, completionHandler: { [weak self] in
                    NSApp.hide(nil)
                    // Restore alphaValue for the next show
                    window.alphaValue = 1.0
                    self?.isAnimating = false
                })
            }
        } else {
            NSApp.hide(nil)
        }
    }
}
