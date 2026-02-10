import SwiftUI
import WebKit

@main
struct GeminiNextApp: App {
    // Use StateObject to persist the lifecycle even when the window is closed
    @StateObject private var webViewModel = WebViewModel()
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: webViewModel)
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified)
        .commands {
            // Cmd+W: close settings window when focused; hide app when main window is focused
            CommandGroup(replacing: .saveItem) {
                Button("Close Window") {
                    if let keyWindow = NSApp.keyWindow {
                        // The settings window identifier is managed by SwiftUI Settings Scene
                        // The main window has a windowDelegate (AppDelegate), settings window does not
                        if keyWindow.delegate is AppDelegate {
                            NSApp.hide(nil)
                        } else {
                            keyWindow.close()
                        }
                    }
                }
                .keyboardShortcut("w", modifiers: .command)
            }
            // Global Cmd+R to reload, Cmd+[ / Cmd+] for navigation
            CommandMenu("View") {
                Button("Reload Page") {
                    webViewModel.webView.reload()
                }
                .keyboardShortcut("r", modifiers: .command)

                Divider()

                Button("Go Back") {
                    webViewModel.webView.goBack()
                }
                .keyboardShortcut("[", modifiers: .command)

                Button("Go Forward") {
                    webViewModel.webView.goForward()
                }
                .keyboardShortcut("]", modifiers: .command)
            }
        }

        // Standard macOS settings window, opened with Cmd+,
        Settings {
            SettingsView()
        }
    }
}

