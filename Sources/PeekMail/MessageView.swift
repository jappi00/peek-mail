import MailCore
import SwiftUI
import UniformTypeIdentifiers
import WebKit

struct MessageDetailView: View {
    @Environment(HistoryStore.self) private var store
    let item: HistoryItem

    var body: some View {
        switch store.message(for: item) {
        case .success(let message):
            MessageContainer(message: message, item: item)
        case .failure(let error):
            ContentUnavailableView("Couldn't Read Message", systemImage: "exclamationmark.triangle",
                                   description: Text(error.localizedDescription))
                .toolbar {
                    ToolbarItem(placement: .primaryAction) { OpenButton() }
                }
        }
    }
}

/// Switches between the rendered message, its headers and its source.
struct MessageContainer: View {
    let message: MailMessage
    let item: HistoryItem
    @AppStorage("messageViewMode") private var mode: MessageViewMode = .message

    var body: some View {
        Group {
            switch mode {
            case .message: MessageView(message: message, item: item)
            case .headers: HeadersView(headers: message.headers)
            case .source: SourceView(item: item)
            }
        }
        .navigationTitle(message.subject.isEmpty ? "(No Subject)" : message.subject)
        .navigationSubtitle(item.fileName)
        .toolbar {
            // One group keeps the order stable: tabs, then "+" at the far right.
            ToolbarItemGroup(placement: .primaryAction) {
                Picker("View", selection: $mode) {
                    Text("Message").tag(MessageViewMode.message)
                    Text("Headers").tag(MessageViewMode.headers)
                    Text("Source").tag(MessageViewMode.source)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .help("Switch between message, headers and source")
                OpenButton()
            }
        }
    }
}

struct MessageView: View {
    let message: MailMessage
    let item: HistoryItem
    @State private var allowRemoteContent = false

    private var hasRemoteContent: Bool {
        message.htmlBody.map(MailHTML.hasRemoteContent) ?? false
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 16)

            if !message.visibleAttachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(message.visibleAttachments) { AttachmentChip(attachment: $0) }
                    }
                    .padding(.horizontal, 24)
                }
                .padding(.bottom, 14)
            }

            if hasRemoteContent && !allowRemoteContent {
                HStack(spacing: 10) {
                    Image(systemName: "eye.slash.fill")
                        .foregroundStyle(.orange)
                    Text("Remote images are blocked to protect your privacy.")
                        .font(.callout)
                    Spacer(minLength: 8)
                    Button("Load Images") { allowRemoteContent = true }
                        .controlSize(.small)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
            }

            MailWebView(html: MailHTML.document(for: message), allowRemoteContent: allowRemoteContent)
                .background(message.htmlBody != nil ? Color.white : Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.separator))
                .shadow(color: .black.opacity(0.08), radius: 8, y: 2)
                .padding([.horizontal, .bottom], 16)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .navigationTitle(message.subject.isEmpty ? "(No Subject)" : message.subject)
        .navigationSubtitle(item.fileName)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(message.subject.isEmpty ? "(No Subject)" : message.subject)
                .font(.system(size: 22, weight: .bold))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(alignment: .top, spacing: 12) {
                AvatarView(name: message.from?.displayName ?? "?", size: 44)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        if let from = message.from {
                            AddressButton(address: from, font: .headline, style: .plain)
                            if let email = from.email, from.name != nil {
                                Text(email)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                        } else {
                            Text("Unknown Sender").font(.headline)
                        }
                    }
                    RecipientLine(label: "To", addresses: message.to)
                    RecipientLine(label: "Cc", addresses: message.cc)
                    RecipientLine(label: "Bcc", addresses: message.bcc)
                }

                Spacer(minLength: 12)

                if let date = message.date {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(date.formatted(date: .abbreviated, time: .omitted))
                            .font(.subheadline.weight(.medium))
                        Text(date.formatted(date: .omitted, time: .shortened))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

struct RecipientLine: View {
    let label: String
    let addresses: [MailAddress]
    @State private var expanded = false
    private let collapsedLimit = 8

    private var visible: [MailAddress] {
        expanded ? addresses : Array(addresses.prefix(collapsedLimit))
    }

    var body: some View {
        if !addresses.isEmpty {
            HStack(alignment: .top, spacing: 6) {
                Text(label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 26, alignment: .leading)
                    .padding(.top, 3)
                FlowLayout(spacing: 4) {
                    ForEach(Array(visible.enumerated()), id: \.offset) { _, address in
                        AddressButton(address: address)
                    }
                    if addresses.count > collapsedLimit {
                        Button(expanded ? "Show Less" : "+\(addresses.count - collapsedLimit) more") {
                            expanded.toggle()
                        }
                        .buttonStyle(.link)
                        .font(.caption)
                        .padding(.top, 3)
                    }
                }
            }
        }
    }
}

/// A name that reveals the full address in a popover when clicked.
struct AddressButton: View {
    enum Style { case chip, plain }

    let address: MailAddress
    var font: Font = .subheadline
    var style: Style = .chip
    @State private var isShowingCard = false
    @State private var isHovering = false

    var body: some View {
        Button { isShowingCard.toggle() } label: {
            Text(address.displayName)
                .font(font)
                .lineLimit(1)
                .underline(style == .plain && isHovering)
                .padding(.horizontal, style == .chip ? 7 : 0)
                .padding(.vertical, style == .chip ? 2 : 0)
                .background {
                    if style == .chip {
                        Capsule().fill(Color.primary.opacity(isHovering ? 0.14 : 0.07))
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(address.formatted)
        .onHover { hovering in
            isHovering = hovering
            if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
        .popover(isPresented: $isShowingCard, arrowEdge: .bottom) {
            AddressCard(address: address)
        }
    }
}

struct AddressCard: View {
    let address: MailAddress
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                AvatarView(name: address.displayName, size: 42)
                VStack(alignment: .leading, spacing: 2) {
                    Text(address.name ?? address.email ?? "Unknown")
                        .font(.headline)
                        .textSelection(.enabled)
                    if let email = address.email {
                        Text(email)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    } else {
                        Text("No email address in this message")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            if let email = address.email {
                HStack(spacing: 8) {
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(email, forType: .string)
                        copied = true
                    } label: {
                        Label(copied ? "Copied" : "Copy Address", systemImage: copied ? "checkmark" : "doc.on.doc")
                    }
                    Button {
                        let encoded = email.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? email
                        if let url = URL(string: "mailto:\(encoded)") { NSWorkspace.shared.open(url) }
                    } label: {
                        Label("New Email", systemImage: "square.and.pencil")
                    }
                }
                .controlSize(.small)
            }
        }
        .padding(16)
        .frame(minWidth: 260, alignment: .leading)
    }
}

/// Lays out children left to right, wrapping onto new rows when out of space.
struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(width: proposal.width ?? .infinity, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(width: bounds.width, subviews: subviews)
        for (index, frame) in result.frames.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                proposal: ProposedViewSize(frame.size))
        }
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> (frames: [CGRect], size: CGSize) {
        var frames: [CGRect] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxX: CGFloat = 0
        for subview in subviews {
            var size = subview.sizeThatFits(.unspecified)
            size.width = min(size.width, width)
            if x > 0 && x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            maxX = max(maxX, x - spacing)
        }
        return (frames, CGSize(width: maxX, height: y + rowHeight))
    }
}

struct AttachmentChip: View {
    let attachment: MailAttachment

    private var icon: NSImage {
        let ext = (attachment.filename as NSString).pathExtension
        let type = UTType(filenameExtension: ext) ?? UTType(mimeType: attachment.mimeType) ?? .data
        return NSWorkspace.shared.icon(for: type)
    }

    var body: some View {
        Button(action: open) {
            HStack(spacing: 8) {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 28, height: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text(attachment.filename)
                        .font(.callout)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(ByteCountFormatter.string(fromByteCount: Int64(attachment.data.count), countStyle: .file))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: 220, alignment: .leading)
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 9))
            .contentShape(RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
        .help("Open \(attachment.filename)")
        .contextMenu {
            Button("Open", action: open)
            Button("Save As…", action: saveAs)
        }
    }

    private func temporaryURL() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PeekMail", isDirectory: true)
            .appendingPathComponent(attachment.id.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(attachment.filename.replacingOccurrences(of: "/", with: "-"))
        try attachment.data.write(to: url)
        return url
    }

    private func open() {
        guard let url = try? temporaryURL() else { return }
        if HistoryStore.supportedExtensions.contains(url.pathExtension.lowercased()) {
            HistoryStore.shared.open([url]) // attached emails open right here
        } else {
            NSWorkspace.shared.open(url)
        }
    }

    private func saveAs() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = attachment.filename
        if panel.runModal() == .OK, let url = panel.url {
            try? attachment.data.write(to: url)
        }
    }
}

/// WebKit registers itself as a drag destination and swallows file drops;
/// refusing drag types lets drops fall through to the window's drop handler.
final class NonDropWebView: WKWebView {
    override func registerForDraggedTypes(_ newTypes: [NSPasteboard.PasteboardType]) {}
}

struct MailWebView: NSViewRepresentable {
    let html: String
    let allowRemoteContent: Bool

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = false
        let webView = NonDropWebView(frame: .zero, configuration: config)
        webView.unregisterDraggedTypes()
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let coordinator = context.coordinator
        guard coordinator.loadedHTML != html || coordinator.loadedAllowRemote != allowRemoteContent else { return }
        coordinator.loadedHTML = html
        coordinator.loadedAllowRemote = allowRemoteContent
        coordinator.generation += 1
        let generation = coordinator.generation
        let html = html
        let allowRemote = allowRemoteContent

        Task { @MainActor in
            let blockList = allowRemote ? nil : await Self.remoteContentBlockList()
            // A newer load started while compiling; let that one configure the web view.
            guard generation == coordinator.generation else { return }
            // Fail closed: if the block list can't be compiled, don't load the mail at all.
            if !allowRemote && blockList == nil { return }

            let controller = webView.configuration.userContentController
            controller.removeAllContentRuleLists()
            if let blockList { controller.add(blockList) }
            webView.loadHTMLString(html, baseURL: nil)
        }
    }

    @MainActor private static var cachedBlockList: WKContentRuleList?

    /// Blocks every network request; inline `data:` images and the document itself still load.
    @MainActor private static func remoteContentBlockList() async -> WKContentRuleList? {
        if let cachedBlockList { return cachedBlockList }
        // Content blocker regexes don't support disjunctions, so one rule per scheme.
        let rules = ["^https?://", "^ftp://", "^wss?://"]
            .map { #"{"trigger":{"url-filter":"\#($0)"},"action":{"type":"block"}}"# }
            .joined(separator: ",")
        let ruleList = "[\(rules)]"
        let list = try? await WKContentRuleListStore.default()
            .compileContentRuleList(forIdentifier: "BlockRemoteContent", encodedContentRuleList: ruleList)
        cachedBlockList = list
        return list
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var loadedHTML: String?
        var loadedAllowRemote: Bool?
        var generation = 0

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
            if navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url {
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }
    }
}

enum MailHTML {
    static func document(for message: MailMessage) -> String {
        if let html = message.resolvedHTML {
            return """
            <meta charset="utf-8">
            <style>
              html { background: #fff; }
              body { margin: 0; padding: 24px 28px; font: 14px/1.5 -apple-system, "Helvetica Neue", sans-serif;
                     color: #1d1d1f; word-wrap: break-word; }
              blockquote { border-left: 3px solid #d0d0d5; margin-left: 0; padding-left: 12px; color: #555; }
            </style>
            \(html)
            """
        }
        return """
        <!doctype html><html><head><meta charset="utf-8">
        <style>
          :root { color-scheme: light dark; }
          body { margin: 0; padding: 24px 28px; font: 14px/1.6 -apple-system, sans-serif; background: transparent; }
          pre { white-space: pre-wrap; word-wrap: break-word; font: inherit; margin: 0; }
          a { color: #0a84ff; }
        </style></head>
        <body><pre>\(linkified(message.textBody ?? ""))</pre></body></html>
        """
    }

    private static let remoteContentRegex = try! NSRegularExpression(
        pattern: #"\b(src|srcset|background|poster)\s*=\s*["']?[^"'>]*?(https?:)?//|url\(\s*["']?\s*(https?:)?//|@import|<link[^>]+href\s*=\s*["']?\s*(https?:)?//"#,
        options: .caseInsensitive)

    /// Whether the HTML references images, stylesheets or fonts on the network.
    static func hasRemoteContent(_ html: String) -> Bool {
        remoteContentRegex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)) != nil
    }

    private static let urlRegex = try! NSRegularExpression(pattern: #"https?://[^\s<>"]+"#)

    private static func linkified(_ text: String) -> String {
        let escaped = text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
        let range = NSRange(escaped.startIndex..., in: escaped)
        return urlRegex.stringByReplacingMatches(in: escaped, range: range, withTemplate: #"<a href="$0">$0</a>"#)
    }
}
