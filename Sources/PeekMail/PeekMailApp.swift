import AppKit
import SwiftUI

@main
struct PeekMailApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store = HistoryStore.shared

    var body: some Scene {
        Window("Peek Mail", id: "main") {
            ContentView()
                .environment(store)
                .frame(minWidth: 780, minHeight: 500)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open…") { store.presentOpenPanel() }
                    .keyboardShortcut("o")
            }
            CommandGroup(after: .newItem) {
                Button("Clear History…", role: .destructive) { store.isConfirmingClear = true }
                    .disabled(store.items.isEmpty)
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
    }

    /// Called when files are opened from Finder (double-click, "Open With", dropping on the Dock icon).
    func application(_ application: NSApplication, open urls: [URL]) {
        HistoryStore.shared.open(urls)
        NSApp.activate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
