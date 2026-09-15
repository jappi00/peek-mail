import Foundation
import MailCore

// Debug helper: prints what the parser extracts from mail files.
for path in CommandLine.arguments.dropFirst() {
    print("== \(path)")
    do {
        let m = try MailParser.parse(data: Data(contentsOf: URL(fileURLWithPath: path)))
        print("Subject: \(m.subject)")
        print("From:    \(m.from?.formatted ?? "-")")
        print("To:      \(m.to.map(\.formatted).joined(separator: ", "))")
        print("Cc:      \(m.cc.map(\.formatted).joined(separator: ", "))")
        print("Date:    \(m.date.map { "\($0)" } ?? "-")")
        print("HTML:    \(m.htmlBody.map { "\($0.count) chars: \($0.prefix(300))" } ?? "-")")
        print("Text:    \(m.textBody.map { "\($0.count) chars: \($0.prefix(300))" } ?? "-")")
        for a in m.attachments {
            print("Attach:  \(a.filename) [\(a.mimeType)] \(a.data.count) bytes cid=\(a.contentID ?? "-")")
        }
        print("Visible attachments: \(m.visibleAttachments.count)")
        print("Headers: \(m.headers.count)")
        for h in m.headers.prefix(5) {
            print("  \(h.name): \(h.decodedValue.prefix(80))")
        }
        let source = MailParser.sourceText(data: try Data(contentsOf: URL(fileURLWithPath: path)))
        print("Source: \(source.count) chars, starts: \(source.prefix(120).replacingOccurrences(of: "\n", with: "⏎"))")
        let spans = SourceHighlighter.spans(for: source, isMSGDump: path.lowercased().hasSuffix(".msg"))
        let counts = Dictionary(grouping: spans, by: { "\($0.style)" }).mapValues(\.count)
        print("Highlight: " + counts.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " "))
        let ns = source as NSString
        for style in [SourceHighlighter.Style.headerName, .pass, .fail, .boundary, .section] {
            if let span = spans.first(where: { $0.style == style }) {
                print("  first \(style): \(ns.substring(with: span.range).prefix(70))")
            }
        }
    } catch {
        print("ERROR: \(error.localizedDescription)")
    }
}
