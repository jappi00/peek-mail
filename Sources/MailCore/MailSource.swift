import Foundation

extension MailParser {
    private static let sourceLimit = 8_000_000

    /// Debug view of a mail file: the raw text for .eml, an extracted dump for binary .msg files.
    public static func sourceText(data: Data) -> String {
        if data.starts(with: oleSignature) {
            return msgDump(data)
        }
        let slice = data.prefix(sourceLimit)
        var text = String(data: slice, encoding: .utf8) ?? String(decoding: slice, as: UTF8.self)
        if data.count > sourceLimit {
            let total = ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file)
            text += "\n\n… truncated, file is \(total)"
        }
        return text
    }

    private static func msgDump(_ data: Data) -> String {
        guard let m = try? MSGParser.parse(data) else {
            return "This Outlook message could not be read."
        }
        var out = """
        ; Outlook .msg files are binary (OLE compound documents), so there is no raw MIME source.
        ; Below are the transport headers and bodies extracted from the file.

        """
        func section(_ title: String, _ body: String?) {
            out += "\n===== \(title) =====\n\n" + (body?.nonEmpty ?? "(none)") + "\n"
        }
        section("Transport Headers", m.transportHeaders)
        section("HTML Body", m.htmlBody)
        section("Plain Text Body", m.textBody)
        section("Attachments", m.attachments.map { att in
            "\(att.filename)  [\(att.mimeType)]  \(att.data.count) bytes" + (att.contentID.map { "  cid:\($0)" } ?? "")
        }.joined(separator: "\n"))
        return out
    }
}
