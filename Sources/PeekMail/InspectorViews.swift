import AppKit
import MailCore
import SwiftUI

enum MessageViewMode: String, CaseIterable {
    case message, headers, source
}

/// Find controls shared by the Headers and Source views: field, match counter, previous/next and ⌘F.
struct SearchControls: View {
    @Bindable var finder: SourceFinder
    let placeholder: String
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 4) {
            TextField(placeholder, text: $finder.query)
                .textFieldStyle(.roundedBorder)
                .frame(width: 180)
                .focused($isFocused)
                .onSubmit { finder.next() }
            if !finder.query.isEmpty {
                Text(finder.matches.isEmpty ? "No matches" : "\(finder.current + 1) of \(finder.matches.count)")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(finder.matches.isEmpty ? Color.red : Color.secondary)
                    .fixedSize(horizontal: true, vertical: false)
                Button { finder.previous() } label: { Image(systemName: "chevron.up") }
                    .disabled(finder.matches.isEmpty)
                    .help("Previous match")
                Button { finder.next() } label: { Image(systemName: "chevron.down") }
                    .disabled(finder.matches.isEmpty)
                    .help("Next match (Return)")
            }
        }
        .background {
            Button("") { isFocused = true }
                .keyboardShortcut("f")
                .opacity(0)
                .accessibilityHidden(true)
        }
    }
}

struct HeadersView: View {
    let headers: [MailHeader]
    @State private var finder = SourceFinder()

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "list.bullet.rectangle")
                    .foregroundStyle(.secondary)
                Text("\(headers.count) headers")
                    .font(.callout)
                    .lineLimit(1)
                Spacer()
                SearchControls(finder: finder, placeholder: "Find in headers")
                Button {
                    let text = headers.map { "\($0.name): \($0.value)" }.joined(separator: "\n")
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                } label: {
                    Label("Copy All", systemImage: "doc.on.doc")
                }
                .disabled(headers.isEmpty)
            }
            .controlSize(.small)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            Divider()

            if headers.isEmpty {
                ContentUnavailableView("No Headers", systemImage: "list.bullet.rectangle",
                                       description: Text("This message doesn't contain transport headers."))
            } else {
                let content = Self.content(for: headers)
                SourceTextView(text: content.text, spans: content.spans, finder: finder, columnWidth: content.columnWidth)
            }
        }
    }

    /// One "Name:<tab>value" paragraph per header, with the decoded value on an indented line below when it differs.
    static func content(for headers: [MailHeader]) -> (text: String, spans: [SourceHighlighter.Span], columnWidth: CGFloat) {
        var text = ""
        var length = 0 // UTF-16 length of `text`
        var decodedSpans: [SourceHighlighter.Span] = []

        for (index, header) in headers.enumerated() {
            if index > 0 {
                text += "\n"
                length += 1
            }
            let line = "\(header.name):\t\(header.value)"
            text += line
            length += (line as NSString).length
            if header.decodedValue != header.value {
                let decodedLine = "\n\t\(header.decodedValue)"
                decodedSpans.append(SourceHighlighter.Span(
                    range: NSRange(location: length + 2, length: (header.decodedValue as NSString).length),
                    style: .comment))
                text += decodedLine
                length += (decodedLine as NSString).length
            }
        }

        let longestName = min(headers.map { ($0.name as NSString).length }.max() ?? 0, 32) + 2
        let nameWidth = (String(repeating: "M", count: longestName) as NSString)
            .size(withAttributes: [.font: SourceTextView.boldFont]).width
        // Decoded spans first so address/encoded-word colors still show on top.
        return (text, decodedSpans + SourceHighlighter.spans(for: text, isMSGDump: false), nameWidth + 12)
    }
}

struct SourceView: View {
    let item: HistoryItem
    @State private var text: String?
    @State private var spans: [SourceHighlighter.Span] = []
    @State private var finder = SourceFinder()

    private var isMSG: Bool { item.storedName.lowercased().hasSuffix(".msg") }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "chevron.left.forwardslash.chevron.right")
                    .foregroundStyle(.secondary)
                Text(isMSG ? "Extracted data (.msg is a binary format)" : "Raw source")
                    .font(.callout)
                    .lineLimit(1)
                Spacer()
                SearchControls(finder: finder, placeholder: "Find in source")
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text ?? "", forType: .string)
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .disabled(text == nil)
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([HistoryStore.shared.fileURL(for: item)])
                } label: {
                    Label("Show File", systemImage: "folder")
                }
            }
            .controlSize(.small)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            Divider()

            if let text {
                SourceTextView(text: text, spans: spans, finder: finder)
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task {
            let url = HistoryStore.shared.fileURL(for: item)
            let isMSG = isMSG
            let loaded = await Task.detached { () -> (String, [SourceHighlighter.Span]) in
                let text = (try? Data(contentsOf: url)).map(MailParser.sourceText(data:)) ?? "Could not read the file."
                return (text, SourceHighlighter.spans(for: text, isMSGDump: isMSG))
            }.value
            spans = loaded.1
            text = loaded.0
        }
    }
}

/// Searches a text view and marks matches with temporary background colors.
@MainActor
@Observable
final class SourceFinder {
    var query = "" {
        didSet { if query != oldValue { runSearch() } }
    }
    private(set) var matches: [NSRange] = []
    private(set) var current = 0

    @ObservationIgnored private weak var textView: NSTextView?
    private static let maxMatches = 10_000
    private static let matchColor = NSColor.systemYellow.withAlphaComponent(0.35)
    private static let currentColor = NSColor.systemOrange.withAlphaComponent(0.65)

    func attach(_ textView: NSTextView) {
        self.textView = textView
        if !query.isEmpty { runSearch() }
    }

    func next() { move(by: 1) }
    func previous() { move(by: -1) }

    private func runSearch() {
        guard let textView, let layout = textView.layoutManager else { return }
        let text = textView.string as NSString
        let full = NSRange(location: 0, length: text.length)
        layout.removeTemporaryAttribute(.backgroundColor, forCharacterRange: full)
        matches = []
        current = 0
        guard !query.isEmpty else { return }

        var remaining = full
        var found: [NSRange] = []
        while found.count < Self.maxMatches {
            let range = text.range(of: query, options: .caseInsensitive, range: remaining)
            guard range.location != NSNotFound, range.length > 0 else { break }
            found.append(range)
            let next = range.location + range.length
            remaining = NSRange(location: next, length: text.length - next)
        }
        for range in found {
            layout.addTemporaryAttribute(.backgroundColor, value: Self.matchColor, forCharacterRange: range)
        }
        matches = found
        revealCurrent()
    }

    private func move(by delta: Int) {
        guard !matches.isEmpty, let layout = textView?.layoutManager else { return }
        layout.addTemporaryAttribute(.backgroundColor, value: Self.matchColor, forCharacterRange: matches[current])
        current = (current + delta + matches.count) % matches.count
        revealCurrent()
    }

    private func revealCurrent() {
        guard !matches.isEmpty, let textView, let layout = textView.layoutManager else { return }
        let range = matches[current]
        layout.addTemporaryAttribute(.backgroundColor, value: Self.currentColor, forCharacterRange: range)
        textView.scrollRangeToVisible(range)
        textView.showFindIndicator(for: range)
    }
}

/// Read-only monospaced text view with syntax colors; AppKit keeps large sources fast.
struct SourceTextView: NSViewRepresentable {
    let text: String
    let spans: [SourceHighlighter.Span]
    let finder: SourceFinder
    /// When set, text after the first tab aligns to this column and wrapped lines indent to it.
    var columnWidth: CGFloat?

    static let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    static let boldFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .semibold)

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        let textView = scrollView.documentView as! NSTextView
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.textContainerInset = NSSize(width: 12, height: 12)
        textView.layoutManager?.allowsNonContiguousLayout = true
        textView.string = text
        textView.font = Self.font
        textView.textColor = .textColor

        if let storage = textView.textStorage {
            storage.beginEditing()
            if let columnWidth {
                let paragraph = NSMutableParagraphStyle()
                paragraph.tabStops = [NSTextTab(textAlignment: .left, location: columnWidth)]
                paragraph.defaultTabInterval = 28
                paragraph.headIndent = columnWidth
                paragraph.paragraphSpacing = 3
                storage.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: storage.length))
            }
            for span in spans where NSMaxRange(span.range) <= storage.length {
                storage.addAttributes(Self.attributes(for: span.style), range: span.range)
            }
            storage.endEditing()
        }
        finder.attach(textView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {}

    private static func attributes(for style: SourceHighlighter.Style) -> [NSAttributedString.Key: Any] {
        switch style {
        case .headerName: return [.foregroundColor: NSColor.systemPurple, .font: boldFont]
        case .encodedWord: return [.foregroundColor: NSColor.systemOrange]
        case .address: return [.foregroundColor: NSColor.systemBlue]
        case .boundary: return [.foregroundColor: NSColor.secondaryLabelColor, .font: boldFont]
        case .encodedData: return [.foregroundColor: NSColor.tertiaryLabelColor]
        case .htmlTag: return [.foregroundColor: NSColor.systemTeal]
        case .comment: return [.foregroundColor: NSColor.secondaryLabelColor]
        case .section: return [.foregroundColor: NSColor.controlAccentColor, .font: boldFont]
        case .pass: return [.foregroundColor: NSColor.systemGreen, .font: boldFont]
        case .fail: return [.foregroundColor: NSColor.systemRed, .font: boldFont]
        case .neutral: return [.foregroundColor: NSColor.systemOrange, .font: boldFont]
        }
    }
}
