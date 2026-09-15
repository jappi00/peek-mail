import AppKit
import Combine
import Sparkle
import SwiftUI

/// Sparkle-based updates. Instead of Sparkle's own prompt on the second launch,
/// Peek Mail asks once on first launch and explains exactly what a check sends.
@MainActor
final class AppUpdater: NSObject, ObservableObject, SPUUpdaterDelegate {
    static let shared = AppUpdater()

    @Published private(set) var canCheckForUpdates = false
    @Published var automaticallyChecksForUpdates = false {
        didSet {
            if updater.automaticallyChecksForUpdates != automaticallyChecksForUpdates {
                updater.automaticallyChecksForUpdates = automaticallyChecksForUpdates
            }
        }
    }

    static let privacyNote = "Each check downloads a small update list, served by Cloudflare and GitHub. They see your IP address and your Peek Mail version. Nothing else is sent, and never anything about your emails."
    // Kept on its own line so the domain isn't hyphenated.
    static let updateSource = "Update list: peekmail.oesterl.ing"

    private static let askedKey = "PeekMailAskedAboutAutomaticUpdates"
    private var controller: SPUStandardUpdaterController!
    var updater: SPUUpdater { controller.updater }

    private override init() {
        super.init()
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: self, userDriverDelegate: nil)
        updater.sendsSystemProfile = false
        updater.publisher(for: \.canCheckForUpdates).assign(to: &$canCheckForUpdates)
        automaticallyChecksForUpdates = updater.automaticallyChecksForUpdates
    }

    func checkForUpdates() {
        updater.checkForUpdates()
    }

    /// Asks once whether Peek Mail may check for updates automatically.
    func askAboutAutomaticChecksIfNeeded() {
        let defaults = UserDefaults.standard
        // Demo and screenshot sessions (see HistoryStore) never ask.
        guard !defaults.bool(forKey: Self.askedKey), defaults.string(forKey: "PeekMailDataDirectory") == nil else { return }

        let alert = NSAlert()
        alert.messageText = "Check for updates automatically?"
        alert.informativeText = """
        Peek Mail can check once a day whether a new version is available, so you get fixes and improvements. \
        You always decide whether to install an update.

        \(Self.privacyNote)
        \(Self.updateSource)

        You can change this anytime in Settings.
        """
        alert.addButton(withTitle: "Check Automatically")
        alert.addButton(withTitle: "Don't Check")
        let allowed = alert.runModal() == .alertFirstButtonReturn

        automaticallyChecksForUpdates = allowed
        defaults.set(true, forKey: Self.askedKey)
    }

    // MARK: SPUUpdaterDelegate

    nonisolated func updaterShouldPromptForPermissionToCheck(forUpdates updater: SPUUpdater) -> Bool {
        false // Peek Mail asks on its own, on first launch.
    }
}

struct SettingsView: View {
    @ObservedObject private var updater = AppUpdater.shared

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }

    var body: some View {
        Form {
            Section {
                Toggle("Automatically check for updates", isOn: $updater.automaticallyChecksForUpdates)
                Text("Checks once a day. \(AppUpdater.privacyNote)\n\(AppUpdater.updateSource)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("Check Now") { updater.checkForUpdates() }
                        .disabled(!updater.canCheckForUpdates)
                    Spacer()
                    Text("Version \(version)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Updates")
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }
}
