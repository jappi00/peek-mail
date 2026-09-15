import SwiftUI

/// Toolbar "+" button; each detail state places it last so it sits at the far right.
struct OpenButton: View {
    var body: some View {
        Button { HistoryStore.shared.presentOpenPanel() } label: {
            Label("Open", systemImage: "plus")
        }
        .help("Open .eml or .msg files")
    }
}
