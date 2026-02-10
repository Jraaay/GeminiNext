import WebKit

class GeminiBaseWebView: WKWebView {
    /// Prevent recursion when re-dispatching the Enter key
    private var isPostingEnter = false

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // Support standard Command shortcuts (e.g. Cmd+C, Cmd+V, Cmd+A)
        if event.modifierFlags.contains(.command) {
            return super.performKeyEquivalent(with: event)
        }
        
        // For regular keys (e.g. Enter), return false so they are passed to the web page as normal key events
        // This fixes an issue where WKWebView in SwiftUI may intercept certain keys as menu shortcuts
        return false
    }

    override func keyDown(with event: NSEvent) {
        // If this is a re-dispatched Enter key, pass directly to super
        if isPostingEnter {
            super.keyDown(with: event)
            return
        }

        super.keyDown(with: event)

        // Enter key (keyCode 36), excluding Shift+Enter
        if event.keyCode == 36 && !event.modifierFlags.contains(.shift) {
            // Check via JS whether an IME composition just ended
            evaluateJavaScript("window.__imeJustEnded || false") { [weak self] result, _ in
                guard let self = self else { return }
                if let justEnded = result as? Bool, justEnded {
                    // Clear the flag
                    self.evaluateJavaScript("window.__imeJustEnded = false", completionHandler: nil)
                    // Delay one frame then re-dispatch a real Enter key event
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        self.postRealEnterKey()
                    }
                }
            }
        }
    }

    /// Re-dispatch a real Enter key event via system-level CGEvent
    /// Unlike JavaScript synthetic events, this produces events with isTrusted = true
    private func postRealEnterKey() {
        guard let window = self.window else { return }
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return }

        isPostingEnter = true
        defer { isPostingEnter = false }

        // Send keyDown
        if let cgDown = CGEvent(keyboardEventSource: source, virtualKey: 0x24, keyDown: true) {
            cgDown.flags = []
            if let nsDown = NSEvent(cgEvent: cgDown) {
                window.sendEvent(nsDown)
            }
        }

        // Send keyUp
        if let cgUp = CGEvent(keyboardEventSource: source, virtualKey: 0x24, keyDown: false) {
            cgUp.flags = []
            if let nsUp = NSEvent(cgEvent: cgUp) {
                window.sendEvent(nsUp)
            }
        }
    }

    /// IME composition-end marker script injection is handled via WKUserScript in WebViewModel
    /// No manual injection is needed here
}
