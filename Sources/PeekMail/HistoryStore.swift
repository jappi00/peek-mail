import AppKit
import CryptoKit
import MailCore
import Observation
import UniformTypeIdentifiers

struct HistoryItem: Codable, Identifiable, Hashable {
    var id: UUID
    var fileName: String
    var storedName: String
    var subject: String
    var sender: String
    var date: Date?
    var addedAt: Date
    var hash: String
}

/// Keeps a copy of every opened mail in Application Support so history survives the original moving.
@MainActor
@Observable
final class HistoryStore {
    static let shared = HistoryStore()
    static let supportedExtensions: Set<String> = ["eml", "msg"]

    var items: [HistoryItem] = []
    var selection: UUID?
    var errorMessage: String?
    var isConfirmingClear = false

    @ObservationIgnored private var cache: [UUID: MailMessage] = [:]
    @ObservationIgnored private let directory: URL
    @ObservationIgnored private var indexURL: URL { directory.appendingPathComponent("history.json") }

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        directory = base.appendingPathComponent("PeekMail", isDirectory: true)
        // Carry over history from when the app was called "Mail Viewer".
        let legacy = base.appendingPathComponent("MailViewer", isDirectory: true)
        if !FileManager.default.fileExists(atPath: directory.path), FileManager.default.fileExists(atPath: legacy.path) {
            try? FileManager.default.moveItem(at: legacy, to: directory)
        }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: indexURL),
           let decoded = try? JSONDecoder().decode([HistoryItem].self, from: data) {
            items = decoded
            selection = decoded.first?.id
        }
    }

    func open(_ urls: [URL]) {
        var failures: [String] = []
        for url in urls {
            guard Self.supportedExtensions.contains(url.pathExtension.lowercased()) else {
                failures.append("\(url.lastPathComponent): only .eml and .msg files are supported.")
                continue
            }
            do {
                let data = try Data(contentsOf: url)
                let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()

                if let existing = items.firstIndex(where: { $0.hash == hash }) {
                    var item = items.remove(at: existing)
                    item.addedAt = .now
                    items.insert(item, at: 0)
                    selection = item.id
                    continue
                }

                let message = try MailParser.parse(data: data)
                let id = UUID()
                let storedName = "\(id.uuidString).\(url.pathExtension.lowercased())"
                try data.write(to: directory.appendingPathComponent(storedName))
                let item = HistoryItem(
                    id: id, fileName: url.lastPathComponent, storedName: storedName,
                    subject: message.subject, sender: message.from?.displayName ?? "Unknown Sender",
                    date: message.date, addedAt: .now, hash: hash)
                cache[id] = message
                items.insert(item, at: 0)
                selection = id
            } catch {
                failures.append("\(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
        if !failures.isEmpty { errorMessage = failures.joined(separator: "\n") }
        save()
    }

    func message(for item: HistoryItem) -> Result<MailMessage, Error> {
        if let cached = cache[item.id] { return .success(cached) }
        return Result {
            let message = try MailParser.parse(data: Data(contentsOf: fileURL(for: item)))
            cache[item.id] = message
            return message
        }
    }

    func fileURL(for item: HistoryItem) -> URL {
        directory.appendingPathComponent(item.storedName)
    }

    func remove(_ ids: Set<UUID>) {
        for item in items where ids.contains(item.id) {
            try? FileManager.default.removeItem(at: fileURL(for: item))
            cache[item.id] = nil
        }
        items.removeAll { ids.contains($0.id) }
        if let selection, ids.contains(selection) { self.selection = items.first?.id }
        save()
    }

    func clear() {
        remove(Set(items.map(\.id)))
    }

    func presentOpenPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = Self.supportedExtensions.compactMap { UTType(filenameExtension: $0) }
        if panel.runModal() == .OK { open(panel.urls) }
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        try? encoder.encode(items).write(to: indexURL, options: .atomic)
    }
}
