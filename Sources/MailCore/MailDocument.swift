import Foundation

/// A self-contained HTML page with a mail's header and body, used for printing, PDF export and Quick Look.
public enum MailDocument {
    public static func standaloneHTML(for message: MailMessage, allowRemoteContent: Bool = false) -> String {
        // Without remote content, only inline (data:) images, styles and fonts may load.
        let csp = allowRemoteContent
            ? ""
            : #"<meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src data:; style-src 'unsafe-inline'; font-src data:">"#

        var rows: [(String, String)] = []
        if let from = message.from { rows.append(("From", escape(from.formatted))) }
        if !message.to.isEmpty { rows.append(("To", escape(message.to.map(\.formatted).joined(separator: ", ")))) }
        if !message.cc.isEmpty { rows.append(("Cc", escape(message.cc.map(\.formatted).joined(separator: ", ")))) }
        if let date = message.date {
            rows.append(("Date", escape(date.formatted(date: .complete, time: .shortened))))
        }
        let attachments = message.visibleAttachments
        if !attachments.isEmpty {
            let list = attachments.map { att in
                "\(escape(att.filename)) <span class=\"pm-size\">(\(ByteCountFormatter.string(fromByteCount: Int64(att.data.count), countStyle: .file)))</span>"
            }.joined(separator: ", ")
            rows.append(("Attachments", list))
        }
        let headerRows = rows.map { "<tr><th>\($0.0)</th><td>\($0.1)</td></tr>" }.joined(separator: "\n")
        let subject = message.subject.isEmpty ? "(No Subject)" : message.subject

        let body: String
        if let html = message.resolvedHTML {
            body = "<div class=\"pm-html\">\(html)</div>"
        } else {
            body = "<pre class=\"pm-text\">\(escape(message.textBody ?? ""))</pre>"
        }

        return """
        <!doctype html>
        <html><head>
        <meta charset="utf-8">
        \(csp)
        <title>\(escape(subject))</title>
        <style>
          html { background: #fff; }
          body { margin: 0; padding: 28px 32px; color: #1d1d1f; font: 14px/1.5 -apple-system, "Helvetica Neue", sans-serif; word-wrap: break-word; }
          .pm-header { border-bottom: 1px solid #d9d9de; padding-bottom: 14px; margin-bottom: 20px; }
          .pm-header h1 { font-size: 20px; line-height: 1.25; margin: 0 0 12px; }
          .pm-header table { border-collapse: collapse; font-size: 13px; }
          .pm-header th { text-align: left; vertical-align: top; color: #6e6e73; font-weight: 600; padding: 2px 14px 2px 0; white-space: nowrap; }
          .pm-header td { padding: 2px 0; }
          .pm-size { color: #8e8e93; }
          .pm-text { white-space: pre-wrap; word-wrap: break-word; font: inherit; margin: 0; }
          @media print { body { padding: 0; } }
        </style>
        </head><body>
        <div class="pm-header">
        <h1>\(escape(subject))</h1>
        <table>
        \(headerRows)
        </table>
        </div>
        \(body)
        </body></html>
        """
    }

    public static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
