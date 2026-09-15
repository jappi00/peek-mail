import SwiftUI

struct ContentView: View {
    @Environment(HistoryStore.self) private var store
    @State private var search = ""
    @State private var isDropTargeted = false

    var body: some View {
        @Bindable var store = store

        NavigationSplitView {
            SidebarView(search: search)
                .navigationSplitViewColumnWidth(min: 230, ideal: 280, max: 400)
        } detail: {
            if let id = store.selection, let item = store.items.first(where: { $0.id == id }) {
                MessageDetailView(item: item)
                    .id(item.id)
            } else {
                DropPlaceholderView()
                    .toolbar {
                        ToolbarItem(placement: .primaryAction) { OpenButton() }
                    }
            }
        }
        .searchable(text: $search, placement: .sidebar, prompt: "Search History")
        .dropDestination(for: URL.self) { urls, _ in
            store.open(urls)
            return true
        } isTargeted: { isDropTargeted = $0 }
        .overlay {
            if isDropTargeted { DropOverlay().transition(.opacity) }
        }
        .animation(.easeOut(duration: 0.15), value: isDropTargeted)
        .alert("Couldn't Open File", isPresented: Binding(
            get: { store.errorMessage != nil },
            set: { if !$0 { store.errorMessage = nil } }
        )) {
            Button("OK") {}
        } message: {
            Text(store.errorMessage ?? "")
        }
    }
}

struct DropPlaceholderView: View {
    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [.blue.opacity(0.25), .purple.opacity(0.2)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 120, height: 120)
                Image(systemName: "envelope.open.fill")
                    .font(.system(size: 50))
                    .foregroundStyle(LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
            }
            Text("Drop Emails Here")
                .font(.title.bold())
            Text("Drag .eml or .msg files into this window,\nor open them from Finder.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct DropOverlay: View {
    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial)
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(style: StrokeStyle(lineWidth: 3, dash: [10, 8]))
                .foregroundStyle(Color.accentColor)
                .padding(24)
            VStack(spacing: 12) {
                Image(systemName: "tray.and.arrow.down.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(Color.accentColor)
                Text("Release to Open")
                    .font(.title2.bold())
            }
        }
        .allowsHitTesting(false)
    }
}
