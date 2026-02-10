import SwiftUI
import WebKit
import Combine

class WebViewModel: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate {

    // MARK: - Constants

    private enum Constants {
        static let geminiURL = URL(string: "https://gemini.google.com/app")!
    }

    /// Settings manager reference
    private let settings = SettingsManager.shared

    /// Subscriptions for observing settings changes
    private var cancellables = Set<AnyCancellable>()

    /// Shared process pool to ensure all WebView instances share the same session, avoiding cookie isolation
    private static let sharedProcessPool = WKProcessPool()

    /// IME composition-end marker script, injected via WKUserScript for reliable timing
    private static let imeFixScript = """
    (function() {
        if (window.__imeFixInstalled) return;
        window.__imeFixInstalled = true;
        window.__imeJustEnded = false;

        document.addEventListener('compositionend', function() {
            window.__imeJustEnded = true;
            setTimeout(function() {
                window.__imeJustEnded = false;
            }, 500);
        }, true);
    })();
    """

    // MARK: - Public Properties

    @Published var isLoading: Bool = true
    @Published var canGoBack: Bool = false
    @Published var canGoForward: Bool = false
    /// Loading error message; non-nil indicates an error occurred
    @Published var errorMessage: String?

    let webView: WKWebView

    /// Background timeout timer; navigates back to homepage on timeout
    private var backgroundTimer: Timer?

    /// Check if currently on the Gemini homepage
    private var isOnHomePage: Bool {
        guard let url = webView.url else { return false }
        return url.host == Constants.geminiURL.host
            && url.path == Constants.geminiURL.path
    }

    // MARK: - Initialization

    override init() {
        let configuration = WKWebViewConfiguration()
        // Use default persistent data store to preserve cookies / LocalStorage across app restarts
        configuration.websiteDataStore = WKWebsiteDataStore.default()
        configuration.processPool = Self.sharedProcessPool
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        // Inject IME fix script via WKUserScript, more reliable than evaluateJavaScript
        let imeScript = WKUserScript(
            source: Self.imeFixScript,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: false
        )
        configuration.userContentController.addUserScript(imeScript)

        webView = GeminiBaseWebView(frame: .zero, configuration: configuration)
        webView.allowsBackForwardNavigationGestures = true
        webView.customUserAgent = settings.userAgent

        super.init()

        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.load(URLRequest(url: Constants.geminiURL))

        // Observe app activation / deactivation events
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidBecomeActive),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidResignActive),

            name: NSApplication.didResignActiveNotification,

            object: nil
        )
    }

    deinit {
        backgroundTimer?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Public Methods

    /// Focus the input field in the page (contenteditable area or textarea)
    func focusInput() {
        let js = """
        (function() {
            // Prefer contenteditable input area (used by Gemini)
            var el = document.querySelector('[contenteditable="true"]');
            if (!el) {
                el = document.querySelector('textarea');
            }
            if (el) {
                el.focus();
            }
        })();
        """
        webView.evaluateJavaScript(js, completionHandler: nil)
    }

    /// When app becomes active, cancel the timer and focus the input field
    @objc private func appDidBecomeActive() {
        backgroundTimer?.invalidate()
        backgroundTimer = nil

        // Delay briefly to ensure the window and WebView are fully ready before focusing
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.focusInput()
        }
    }

    /// 应用进入后台时，启动超时定时器（"永不" 时不启动）
    @objc private func appDidResignActive() {
        backgroundTimer?.invalidate()
        backgroundTimer = nil

        // 选择 "永不" 时不启动定时器
        guard let interval = settings.backgroundTimeout.seconds else { return }

        backgroundTimer = Timer.scheduledTimer(
            withTimeInterval: interval,
            repeats: false
        ) { [weak self] _ in
            guard let self = self, !self.isOnHomePage else { return }
            self.webView.load(URLRequest(url: Constants.geminiURL))
        }
    }

    /// Reload the current page and clear error state; fall back to homepage if no current URL
    func retry() {
        errorMessage = nil
        if webView.url != nil {
            webView.reload()
        } else {
            webView.load(URLRequest(url: Constants.geminiURL))
        }
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        isLoading = true
        errorMessage = nil
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isLoading = false
        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        let nsError = error as NSError
        // Ignore cancellation errors, which are normal navigation cancellations
        if nsError.code != NSURLErrorCancelled {
            print("Navigation failed: \(error.localizedDescription)")
            errorMessage = String(localized: "Failed to load. Please check your network connection.")
        }
        isLoading = false
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        let nsError = error as NSError
        if nsError.code != NSURLErrorCancelled {
            print("Provisional navigation failed: \(error.localizedDescription)")
            errorMessage = String(localized: "Unable to connect to Gemini. Please check your network connection.")
        }
        isLoading = false
    }

    // MARK: - WKUIDelegate

    /// Handle target="_blank" link requests by opening them in the system default browser
    func webView(_ webView: WKWebView,
                 createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url {
            NSWorkspace.shared.open(url)
        }
        return nil
    }
}
