import SwiftUI
import Combine

/// Update check status
enum UpdateStatus: Equatable {
    case idle           // Idle, waiting for check
    case checking       // Checking in progress
    case upToDate       // Already on the latest version
    case available(String) // New version available, with version string
    case error(String)  // Check failed, with error message
}

/// Check for app updates via the GitHub Releases API
class UpdateChecker: ObservableObject {

    static let shared = UpdateChecker()

    // GitHub repository info
    private let owner = "Jraaay"
    private let repo = "GeminiNext"

    @Published var status: UpdateStatus = .idle

    private init() {}

    // MARK: - Public Methods

    /// Check for updates
    /// - Parameter silent: In silent mode, only shows an alert when a new version is found; in non-silent mode, updates UI status even if already up to date
    func checkForUpdate(silent: Bool = false) {
        // Prevent duplicate checks
        guard status != .checking else { return }

        DispatchQueue.main.async {
            self.status = .checking
        }

        let urlString = "https://api.github.com/repos/\(owner)/\(repo)/releases/latest"
        guard let url = URL(string: urlString) else { return }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        // Set timeout to avoid long waits
        request.timeoutInterval = 10

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }

            DispatchQueue.main.async {
                if let error = error {
                    if silent {
                        // Suppress network errors in silent mode
                        self.status = .idle
                    } else {
                        self.status = .error(error.localizedDescription)
                    }
                    return
                }

                guard let httpResponse = response as? HTTPURLResponse else {
                    if !silent { self.status = .error("Invalid response") }
                    else { self.status = .idle }
                    return
                }

                // 404 means no release exists yet
                if httpResponse.statusCode == 404 {
                    if silent {
                        self.status = .idle
                    } else {
                        self.status = .upToDate
                    }
                    return
                }

                guard httpResponse.statusCode == 200,
                      let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let tagName = json["tag_name"] as? String else {
                    if !silent { self.status = .error("Failed to parse response") }
                    else { self.status = .idle }
                    return
                }

                let htmlURL = json["html_url"] as? String

                // Parse remote version (strip "v" prefix)
                let remoteVersion = tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName
                let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"

                if self.isVersion(remoteVersion, newerThan: currentVersion) {
                    self.status = .available(remoteVersion)
                    self.showUpdateAlert(version: remoteVersion, downloadURL: htmlURL)
                } else {
                    if silent {
                        self.status = .idle
                    } else {
                        self.status = .upToDate
                        // Reset to idle after 3 seconds
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                            if self.status == .upToDate {
                                self.status = .idle
                            }
                        }
                    }
                }
            }
        }.resume()
    }

    // MARK: - Private Methods

    /// Semantic version comparison: returns true if v1 is newer than v2
    private func isVersion(_ v1: String, newerThan v2: String) -> Bool {
        let parts1 = v1.split(separator: ".").compactMap { Int($0) }
        let parts2 = v2.split(separator: ".").compactMap { Int($0) }

        // Pad to equal length
        let maxCount = max(parts1.count, parts2.count)
        let padded1 = parts1 + Array(repeating: 0, count: maxCount - parts1.count)
        let padded2 = parts2 + Array(repeating: 0, count: maxCount - parts2.count)

        for i in 0..<maxCount {
            if padded1[i] > padded2[i] { return true }
            if padded1[i] < padded2[i] { return false }
        }
        return false
    }

    /// Show the update alert dialog
    private func showUpdateAlert(version: String, downloadURL: String?) {
        let alert = NSAlert()
        alert.messageText = String(localized: "Update Available")
        alert.informativeText = String(format: String(localized: "A new version %@ is available. Would you like to download it?"), version)
        alert.alertStyle = .informational
        alert.addButton(withTitle: String(localized: "Download"))
        alert.addButton(withTitle: String(localized: "Later"))

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            // Open the Release page
            let urlString = downloadURL ?? "https://github.com/\(owner)/\(repo)/releases/latest"
            if let url = URL(string: urlString) {
                NSWorkspace.shared.open(url)
            }
        }
    }
}
