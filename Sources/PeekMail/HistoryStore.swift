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
/// Reading and parsing happen off the main thread, so large files don't freeze the window.
@MainActor
@Observable
final class HistoryStore {
    static let shared = HistoryStore()
    static let supportedExtensions: Set<String> = ["eml", "msg"]

    var items: [HistoryItem] = []
    var selection: UUID?
    var errorMessage: String?
    var isConfirmingClear = false
    /// Number of files currently being read and parsed.
    private(set) var importsInProgress = 0
    /// Messages for which the user clicked "Load Images" in this session.
    var remoteContentAllowed: Set<UUID> = []

    @ObservationIgnored private var cache: [UUID: MailMessage] = [:]
    @ObservationIgnored private let directory: URL
    @ObservationIgnored private var indexURL: URL { directory.appendingPathComponent("history.json") }

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        if let custom = UserDefaults.standard.string(forKey: "PeekMailDataDirectory") {
            // Launch argument `-PeekMailDataDirectory <path>` keeps demo and screenshot sessions out of the real history.
            directory = URL(fileURLWithPath: (custom as NSString).expandingTildeInPath, isDirectory: true)
        } else {
            directory = base.appendingPathComponent("PeekMail", isDirectory: true)
            // Carry over history from when the app was called "Mail Viewer".
            let legacy = base.appendingPathComponent("MailViewer", isDirectory: true)
            if !FileManager.default.fileExists(atPath: directory.path), FileManager.default.fileExists(atPath: legacy.path) {
                try? FileManager.default.moveItem(at: legacy, to: directory)
            }
        }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: indexURL),
           let decoded = try? JSONDecoder().decode([HistoryItem].self, from: data) {
            items = decoded
            selection = decoded.first?.id
        }
    }

    func open(_ urls: [URL]) {
        Task { await importFiles(urls) }
    }

    private func importFiles(_ urls: [URL]) async {
        var failures: [String] = []
        for url in urls {
            guard Self.supportedExtensions.contains(url.pathExtension.lowercased()) else {
                failures.append("\(url.lastPathComponent): only .eml and .msg files are supported.")
                continue
            }
            importsInProgress += 1
            defer { importsInProgress -= 1 }

            // Read and hash in the background.
            let read = await Task.detached(priority: .userInitiated) { () -> Result<(Data, String), Error> in
                Result {
                    let data = try Data(contentsOf: url)
                    return (data, SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined())
                }
            }.value
            guard case .success(let (data, hash)) = read else {
                if case .failure(let error) = read { failures.append("\(url.lastPathComponent): \(error.localizedDescription)") }
                continue
            }

            if let existing = items.firstIndex(where: { $0.hash == hash }) {
                var item = items.remove(at: existing)
                item.addedAt = .now
                items.insert(item, at: 0)
                selection = item.id
                continue
            }

            // Parse and store the copy in the background.
            let id = UUID()
            let storedURL = directory.appendingPathComponent("\(id.uuidString).\(url.pathExtension.lowercased())")
            let parsed = await Task.detached(priority: .userInitiated) { () -> Result<MailMessage, Error> in
                Result {
                    let message = try MailParser.parse(data: data)
                    try data.write(to: storedURL)
                    return message
                }
            }.value

            switch parsed {
            case .success(let message):
                let item = HistoryItem(
                    id: id, fileName: url.lastPathComponent, storedName: storedURL.lastPathComponent,
                    subject: message.subject, sender: message.from?.displayName ?? "Unknown Sender",
                    date: message.date, addedAt: .now, hash: hash)
                cache[id] = message
                items.insert(item, at: 0)
                selection = id
            case .failure(let error):
                failures.append("\(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
        if !failures.isEmpty { errorMessage = failures.joined(separator: "\n") }
        save()
    }

    func cachedMessage(for item: HistoryItem) -> MailMessage? {
        cache[item.id]
    }

    /// Returns the parsed message, parsing it in the background if it isn't cached yet.
    func loadMessage(for item: HistoryItem) async -> Result<MailMessage, Error> {
        if let cached = cache[item.id] { return .success(cached) }
        let url = fileURL(for: item)
        let result = await Task.detached(priority: .userInitiated) { () -> Result<MailMessage, Error> in
            Result { try MailParser.parse(data: Data(contentsOf: url)) }
        }.value
        if case .success(let message) = result { cache[item.id] = message }
        return result
    }

    var selectedItem: HistoryItem? {
        guard let selection else { return nil }
        return items.first { $0.id == selection }
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
        remoteContentAllowed.subtract(ids)
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
