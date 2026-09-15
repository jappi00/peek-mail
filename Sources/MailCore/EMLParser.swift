import Foundation
import UniformTypeIdentifiers

struct MIMEPart {
    var headers: [(name: String, value: String)] = []
    var body: [UInt8] = []

    init(_ bytes: [UInt8]) {
        var lines: [String] = []
        var lineStart = 0
        var bodyStart = bytes.count
        var i = 0
        while i < bytes.count {
            if bytes[i] == 10 {
                var lineEnd = i
                if lineEnd > lineStart && bytes[lineEnd - 1] == 13 { lineEnd -= 1 }
                if lineEnd == lineStart {
                    bodyStart = i + 1
                    break
                }
                lines.append(EMLParser.headerString(bytes[lineStart..<lineEnd]))
                lineStart = i + 1
            }
            i += 1
        }
        if i >= bytes.count, lineStart < bytes.count {
            lines.append(EMLParser.headerString(bytes[lineStart..<bytes.count]))
        }

        for line in lines {
            if let first = line.first, first == " " || first == "\t" {
                if !headers.isEmpty {
                    headers[headers.count - 1].value += " " + line.trimmed
                }
            } else if let colon = line.firstIndex(of: ":") {
                let name = line[..<colon].trimmed
                let value = line[line.index(after: colon)...].trimmed
                headers.append((name, value))
            }
        }
        if bodyStart < bytes.count {
            body = Array(bytes[bodyStart...])
        }
    }

    /// Looks up a header case-insensitively; `name` must be lowercase.
    func header(_ name: String) -> String? {
        headers.first { $0.name.lowercased() == name }?.value
    }

    var contentType: (type: String, params: [String: String]) {
        let (type, params) = EMLParser.parseParams(header("content-type") ?? "text/plain")
        return (type.isEmpty ? "text/plain" : type, params)
    }
}

enum EMLParser {
    static func parse(_ data: Data) -> MailMessage {
        let root = MIMEPart([UInt8](data))
        var msg = MailMessage()
        msg.subject = root.header("subject").map(decodeWords) ?? ""
        msg.from = parseAddresses(root.header("from")).first
        msg.to = parseAddresses(root.header("to"))
        msg.cc = parseAddresses(root.header("cc"))
        msg.bcc = parseAddresses(root.header("bcc"))
        msg.date = parseDate(root.header("date"))
        msg.headers = root.headers.map { MailHeader(name: $0.name, value: $0.value) }
        collect(root, into: &msg)
        return msg
    }

    static func collect(_ part: MIMEPart, into msg: inout MailMessage) {
        let (type, params) = part.contentType
        let (disposition, dispParams) = parseParams(part.header("content-disposition") ?? "")

        if type.hasPrefix("multipart/"), let boundary = params["boundary"] {
            for sub in splitMultipart(part.body, boundary: boundary) {
                collect(MIMEPart(sub), into: &msg)
            }
            return
        }

        let data = decodeTransfer(part.body, encoding: part.header("content-transfer-encoding"))
        let filename = (dispParams["filename"] ?? params["name"]).map(decodeWords)

        if disposition != "attachment" && filename == nil {
            if type == "text/html" {
                msg.htmlBody = (msg.htmlBody ?? "") + decodeText(data, charset: params["charset"])
                return
            }
            if type == "text/plain" {
                let text = decodeText(data, charset: params["charset"])
                msg.textBody = msg.textBody.map { $0 + "\n\n" + text } ?? text
                return
            }
        }

        var name = filename
        if name == nil {
            if type == "message/rfc822" {
                name = "Attached Message.eml"
            } else {
                let ext = UTType(mimeType: type)?.preferredFilenameExtension.map { ".\($0)" } ?? ""
                name = "attachment-\(msg.attachments.count + 1)\(ext)"
            }
        }
        let cid = part.header("content-id")?.trimmingCharacters(in: CharacterSet(charactersIn: "<> "))
        msg.attachments.append(MailAttachment(filename: name!, mimeType: type, data: Data(data), contentID: cid?.nonEmpty))
    }

    // MARK: - Multipart

    static func splitMultipart(_ body: [UInt8], boundary: String) -> [[UInt8]] {
        let delimiter = Array(("--" + boundary).utf8)
        var parts: [[UInt8]] = []
        var partStart: Int?
        var lineStart = 0
        let n = body.count

        func trimmedEnd(_ end: Int) -> Int {
            var e = end
            if e > 0 && body[e - 1] == 10 { e -= 1 }
            if e > 0 && body[e - 1] == 13 { e -= 1 }
            return e
        }

        while lineStart < n {
            var lineEnd = lineStart
            while lineEnd < n && body[lineEnd] != 10 { lineEnd += 1 }
            let next = min(lineEnd + 1, n)

            if lineEnd - lineStart >= delimiter.count,
               body[lineStart..<(lineStart + delimiter.count)].elementsEqual(delimiter) {
                let rest = lineStart + delimiter.count
                let closing = rest + 1 < n && body[rest] == 45 && body[rest + 1] == 45
                if let start = partStart {
                    let end = max(start, trimmedEnd(lineStart))
                    parts.append(Array(body[start..<end]))
                }
                if closing { return parts }
                partStart = next
            }
            lineStart = next
        }
        if let start = partStart, start < n {
            parts.append(Array(body[start..<n]))
        }
        return parts
    }

    // MARK: - Decoding

    static func headerString(_ bytes: ArraySlice<UInt8>) -> String {
        String(bytes: bytes, encoding: .utf8) ?? String(bytes: bytes, encoding: .isoLatin1) ?? ""
    }

    static func decodeTransfer(_ body: [UInt8], encoding: String?) -> [UInt8] {
        switch encoding?.trimmed.lowercased() {
        case "base64":
            var clean = body.filter { ($0 >= 65 && $0 <= 90) || ($0 >= 97 && $0 <= 122) || ($0 >= 48 && $0 <= 57) || $0 == 43 || $0 == 47 }
            while clean.count % 4 != 0 { clean.append(61) }
            return Data(base64Encoded: Data(clean)).map { [UInt8]($0) } ?? body
        case "quoted-printable":
            return decodeQuotedPrintable(body)
        default:
            return body
        }
    }

    static func hexValue(_ c: UInt8) -> UInt8? {
        switch c {
        case 48...57: return c - 48
        case 65...70: return c - 55
        case 97...102: return c - 87
        default: return nil
        }
    }

    static func decodeQuotedPrintable(_ b: [UInt8], underscoreIsSpace: Bool = false) -> [UInt8] {
        var out: [UInt8] = []
        out.reserveCapacity(b.count)
        var i = 0
        while i < b.count {
            let c = b[i]
            if c == 61 {
                if i + 1 < b.count && b[i + 1] == 10 { i += 2; continue }
                if i + 2 < b.count && b[i + 1] == 13 && b[i + 2] == 10 { i += 3; continue }
                if i + 2 < b.count, let h = hexValue(b[i + 1]), let l = hexValue(b[i + 2]) {
                    out.append(h << 4 | l)
                    i += 3
                    continue
                }
            }
            out.append(underscoreIsSpace && c == 95 ? 32 : c)
            i += 1
        }
        return out
    }

    static func encoding(forCharset charset: String?) -> String.Encoding? {
        guard let cs = charset?.trimmingCharacters(in: CharacterSet(charactersIn: "\"' ")).lowercased(), !cs.isEmpty else { return nil }
        if cs == "utf8" || cs == "utf-8" { return .utf8 }
        let cf = CFStringConvertIANACharSetNameToEncoding(cs as CFString)
        guard cf != kCFStringEncodingInvalidId else { return nil }
        return String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cf))
    }

    static func decodeText(_ bytes: [UInt8], charset: String?) -> String {
        if let enc = encoding(forCharset: charset), let s = String(bytes: bytes, encoding: enc) { return s }
        if let s = String(bytes: bytes, encoding: .utf8) { return s }
        return String(bytes: bytes, encoding: .windowsCP1252) ?? String(decoding: bytes, as: UTF8.self)
    }

    private static let encodedWordRegex = try! NSRegularExpression(pattern: #"=\?([^?\s]+)\?([bBqQ])\?([^?]*)\?="#)

    /// Decodes RFC 2047 encoded words (`=?utf-8?B?...?=`).
    static func decodeWords(_ s: String) -> String {
        let ns = s as NSString
        let matches = encodedWordRegex.matches(in: s, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return s }
        var result = ""
        var last = 0
        var previousWasWord = false
        for m in matches {
            let gap = ns.substring(with: NSRange(location: last, length: m.range.location - last))
            if !(previousWasWord && gap.trimmed.isEmpty) { result += gap }
            let charset = ns.substring(with: m.range(at: 1)).split(separator: "*").first.map(String.init)
            let mode = ns.substring(with: m.range(at: 2)).lowercased()
            let text = ns.substring(with: m.range(at: 3))
            let bytes: [UInt8]
            if mode == "b" {
                bytes = decodeTransfer(Array(text.utf8), encoding: "base64")
            } else {
                bytes = decodeQuotedPrintable(Array(text.utf8), underscoreIsSpace: true)
            }
            result += decodeText(bytes, charset: charset)
            last = m.range.location + m.range.length
            previousWasWord = true
        }
        result += ns.substring(from: last)
        return result
    }

    /// Parses `value; key=val; key*=utf-8''...` style headers (incl. RFC 2231 continuations).
    static func parseParams(_ header: String) -> (String, [String: String]) {
        var segments: [String] = []
        var current = ""
        var inQuotes = false
        var escaped = false
        for ch in header {
            if escaped { current.append(ch); escaped = false; continue }
            if ch == "\\" && inQuotes { escaped = true; continue }
            if ch == "\"" { inQuotes.toggle(); current.append(ch); continue }
            if ch == ";" && !inQuotes { segments.append(current); current = ""; continue }
            current.append(ch)
        }
        segments.append(current)

        let main = segments.first?.trimmed.lowercased() ?? ""
        var simple: [String: String] = [:]
        var extended: [String: [(index: Int, encoded: Bool, value: String)]] = [:]

        for seg in segments.dropFirst() {
            guard let eq = seg.firstIndex(of: "=") else { continue }
            let key = seg[..<eq].trimmed.lowercased()
            var value = seg[seg.index(after: eq)...].trimmed
            if value.hasPrefix("\"") && value.hasSuffix("\"") && value.count >= 2 {
                value = String(value.dropFirst().dropLast())
            }
            if let star = key.firstIndex(of: "*") {
                let base = String(key[..<star])
                let index = key[star...].split(separator: "*").first.flatMap { Int($0) } ?? 0
                extended[base, default: []].append((index, key.hasSuffix("*"), value))
            } else {
                simple[key] = value
            }
        }

        for (base, segs) in extended {
            var charset = "utf-8"
            var bytes: [UInt8] = []
            for seg in segs.sorted(by: { $0.index < $1.index }) {
                var v = seg.value
                if seg.encoded {
                    if seg.index == 0 {
                        let comps = v.split(separator: "'", maxSplits: 2, omittingEmptySubsequences: false)
                        if comps.count == 3 {
                            charset = String(comps[0])
                            v = String(comps[2])
                        }
                    }
                    bytes += percentDecode(v)
                } else {
                    bytes += Array(v.utf8)
                }
            }
            simple[base] = decodeText(bytes, charset: charset)
        }
        return (main, simple)
    }

    static func percentDecode(_ s: String) -> [UInt8] {
        let b = Array(s.utf8)
        var out: [UInt8] = []
        var i = 0
        while i < b.count {
            if b[i] == 37, i + 2 < b.count, let h = hexValue(b[i + 1]), let l = hexValue(b[i + 2]) {
                out.append(h << 4 | l)
                i += 3
            } else {
                out.append(b[i])
                i += 1
            }
        }
        return out
    }

    static func parseAddresses(_ header: String?) -> [MailAddress] {
        guard let header, !header.isEmpty else { return [] }
        var tokens: [String] = []
        var current = ""
        var inQuotes = false
        var angle = 0
        for ch in header {
            switch ch {
            case "\"": inQuotes.toggle()
            case "<" where !inQuotes: angle += 1
            case ">" where !inQuotes: angle = max(0, angle - 1)
            case ",", ";":
                if !inQuotes && angle == 0 {
                    tokens.append(current)
                    current = ""
                    continue
                }
            default: break
            }
            current.append(ch)
        }
        tokens.append(current)

        return tokens.compactMap { raw in
            var token = raw.trimmed
            if let colon = token.firstIndex(of: ":"), !token[..<colon].contains("@"), !token[..<colon].contains("<") {
                token = token[token.index(after: colon)...].trimmed // group syntax
            }
            guard !token.isEmpty else { return nil }
            if let lt = token.lastIndex(of: "<"), let gt = token.lastIndex(of: ">"), lt < gt {
                let email = String(token[token.index(after: lt)..<gt])
                let name = token[..<lt].trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                return MailAddress(name: decodeWords(name), email: email)
            }
            if token.contains("@") {
                let email = token.components(separatedBy: "(").first ?? token
                return MailAddress(name: nil, email: email)
            }
            return MailAddress(name: decodeWords(token), email: nil)
        }
    }

    static func parseDate(_ header: String?) -> Date? {
        guard var s = header?.trimmed, !s.isEmpty else { return nil }
        if let paren = s.firstIndex(of: "(") { s = s[..<paren].trimmed }
        s = s.replacingOccurrences(of: "  ", with: " ")
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let formats = [
            "EEE, d MMM yyyy HH:mm:ss Z", "d MMM yyyy HH:mm:ss Z",
            "EEE, d MMM yyyy HH:mm Z", "d MMM yyyy HH:mm Z",
            "EEE, d MMM yyyy HH:mm:ss zzz", "d MMM yyyy HH:mm:ss zzz",
            "EEE, d MMM yy HH:mm:ss Z",
        ]
        for f in formats {
            formatter.dateFormat = f
            if let d = formatter.date(from: s) { return d }
        }
        return nil
    }
}
