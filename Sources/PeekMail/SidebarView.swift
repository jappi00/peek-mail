import SwiftUI

struct SidebarView: View {
    @Environment(HistoryStore.self) private var store
    let search: String

    private var filtered: [HistoryItem] {
        guard !search.isEmpty else { return store.items }
        return store.items.filter {
            $0.subject.localizedCaseInsensitiveContains(search)
                || $0.sender.localizedCaseInsensitiveContains(search)
                || $0.fileName.localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        @Bindable var store = store

        List(selection: $store.selection) {
            ForEach(filtered) { item in
                HistoryRow(item: item)
                    .contextMenu {
                        Button("Show in Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting([store.fileURL(for: item)])
                        }
                        Divider()
                        Button("Remove from History", role: .destructive) {
                            store.remove([item.id])
                        }
                    }
            }
        }
        .onDeleteCommand {
            if let id = store.selection { store.remove([id]) }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !store.items.isEmpty {
                VStack(spacing: 0) {
                    Divider()
                    HStack {
                        Text("\(store.items.count) \(store.items.count == 1 ? "email" : "emails")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button(role: .destructive) {
                            store.isConfirmingClear = true
                        } label: {
                            Label("Clear All", systemImage: "trash")
                        }
                        .controlSize(.small)
                        .help("Remove all emails from history")
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
                .background(.bar)
            }
        }
        .confirmationDialog("Clear all history?", isPresented: $store.isConfirmingClear) {
            Button("Clear All", role: .destructive) { store.clear() }
        } message: {
            Text("This removes all \(store.items.count) emails from the history. Your original files are not affected.")
        }
        .overlay {
            if store.items.isEmpty {
                ContentUnavailableView("No History", systemImage: "tray", description: Text("Opened emails show up here."))
            } else if filtered.isEmpty {
                ContentUnavailableView.search(text: search)
            }
        }
    }
}

struct HistoryRow: View {
    let item: HistoryItem

    var body: some View {
        HStack(spacing: 10) {
            AvatarView(name: item.sender, size: 34)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
                    Text(item.sender)
                        .font(.headline)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if let date = item.date {
                        Text(date.shortLabel)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Text(item.subject.isEmpty ? "(No Subject)" : item.subject)
                    .font(.subheadline)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Image(systemName: item.fileName.lowercased().hasSuffix(".msg") ? "doc.fill" : "envelope.fill")
                    Text(item.fileName).lineLimit(1).truncationMode(.middle)
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 5)
    }
}

struct AvatarView: View {
    let name: String
    let size: CGFloat

    private var initials: String {
        let words = name.split { !$0.isLetter && !$0.isNumber }.prefix(2)
        let letters = words.compactMap(\.first).map { String($0).uppercased() }.joined()
        return letters.isEmpty ? "?" : letters
    }

    private var hue: Double {
        var hash: UInt32 = 5381
        for byte in name.utf8 { hash = hash &* 33 &+ UInt32(byte) }
        return Double(hash % 360) / 360
    }

    var body: some View {
        Circle()
            .fill(LinearGradient(
                colors: [Color(hue: hue, saturation: 0.55, brightness: 0.95), Color(hue: hue, saturation: 0.75, brightness: 0.7)],
                startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: size, height: size)
            .overlay {
                Text(initials)
                    .font(.system(size: size * 0.38, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
            }
    }
}

extension Date {
    var shortLabel: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(self) { return formatted(date: .omitted, time: .shortened) }
        if calendar.isDateInYesterday(self) { return "Yesterday" }
        if calendar.isDate(self, equalTo: .now, toGranularity: .year) {
            return formatted(.dateTime.day().month(.abbreviated))
        }
        return formatted(date: .numeric, time: .omitted)
    }
}
