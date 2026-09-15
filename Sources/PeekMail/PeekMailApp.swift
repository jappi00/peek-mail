import AppKit
import SwiftUI

@main
struct PeekMailApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store = HistoryStore.shared
    @ObservedObject private var updater = AppUpdater.shared

    var body: some Scene {
        Window("Peek Mail", id: "main") {
            ContentView()
                .environment(store)
                .frame(minWidth: 780, minHeight: 500)
        }
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Peek Mail") { AppInfo.showAboutPanel() }
                Button("Check for Updates…") { updater.checkForUpdates() }
                    .disabled(!updater.canCheckForUpdates)
            }
            CommandGroup(replacing: .help) {
                Link("Peek Mail Website", destination: AppInfo.website)
                Link("Contact Support…", destination: AppInfo.supportMail)
                Divider()
                Link("Report an Issue on GitHub", destination: AppInfo.issues)
                Link("Source Code", destination: AppInfo.sourceCode)
            }
            CommandGroup(replacing: .newItem) {
                Button("Open…") { store.presentOpenPanel() }
                    .keyboardShortcut("o")
            }
            CommandGroup(after: .newItem) {
                Button("Clear History…", role: .destructive) { store.isConfirmingClear = true }
                    .disabled(store.items.isEmpty)
            }
        }

        Settings {
            SettingsView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()

        // Launch argument `-PeekMailWindowSize 1200x760` gives screenshots a consistent window size.
        if let value = UserDefaults.standard.string(forKey: "PeekMailWindowSize") {
            let parts = value.split(separator: "x").compactMap { Double($0) }
            if parts.count == 2 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    guard let window = NSApp.windows.first(where: { $0.isVisible }) else { return }
                    window.setContentSize(NSSize(width: parts[0], height: parts[1]))
                    window.center()
                }
            }
        }

        // Ask about automatic update checks once the main window is on screen.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            AppUpdater.shared.askAboutAutomaticChecksIfNeeded()
        }
    }

    /// Called when files are opened from Finder (double-click, "Open With", dropping on the Dock icon).
    func application(_ application: NSApplication, open urls: [URL]) {
        HistoryStore.shared.open(urls)
        NSApp.activate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
