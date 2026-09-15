import Foundation

/// Finds ranges to colorize in mail source text. Pure Foundation so it runs off the main thread.
public enum SourceHighlighter {
    public enum Style: Sendable {
        case headerName, encodedWord, address, boundary, encodedData, htmlTag
        case comment, section, pass, fail, neutral
    }

    public struct Span: Sendable {
        public let range: NSRange
        public let style: Style

        public init(range: NSRange, style: Style) {
            self.range = range
            self.style = style
        }
    }

    /// Sources larger than this (UTF-16 units) are left plain to keep the viewer responsive.
    public static let maxLength = 2_000_000

    private static let encodedWord = try! NSRegularExpression(pattern: #"=\?[^?\s]+\?[bBqQ]\?[^?]*\?="#)
    private static let address = try! NSRegularExpression(pattern: #"<[^<>\s@]+@[^<>\s]+>"#)
    private static let authResult = try! NSRegularExpression(
        pattern: #"\b(?:spf|dkim|dmarc|arc|auth|compauth)=(pass|bestguesspass|fail|softfail|hardfail|permerror|neutral|none|temperror|policy)\b"#,
        options: .caseInsensitive)
    private static let htmlTag = try! NSRegularExpression(pattern: #"</?[A-Za-z!][^>]*>"#)

    /// - Parameter isMSGDump: the text is the extracted dump of a .msg file (has sections and comments).
    public static func spans(for text: String, isMSGDump: Bool) -> [Span] {
        let ns = text as NSString
        guard ns.length <= maxLength else { return [] }

        var spans: [Span] = []
        // .eml files start with headers; the .msg dump starts with comments.
        var inHeaders = !isMSGDump
        var skipNextBlank = false

        ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length), options: .byLines) { substring, lineRange, _, _ in
            guard let line = substring else { return }
            let lineNS = line as NSString
            let offset = lineRange.location

            func add(_ range: NSRange, _ style: Style) {
                spans.append(Span(range: NSRange(location: range.location + offset, length: range.length), style: style))
            }
            func matches(_ regex: NSRegularExpression) -> [NSTextCheckingResult] {
                regex.matches(in: line, range: NSRange(location: 0, length: lineNS.length))
            }

            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                if skipNextBlank { skipNextBlank = false } else { inHeaders = false }
                return
            }

            if isMSGDump {
                if line.hasPrefix("=====") {
                    add(NSRange(location: 0, length: lineNS.length), .section)
                    inHeaders = line.contains("Headers")
                    skipNextBlank = true
                    return
                }
                if line.hasPrefix(";") {
                    add(NSRange(location: 0, length: lineNS.length), .comment)
                    return
                }
            }

            if line.hasPrefix("--"), lineNS.length > 4, !line.contains(" ") {
                add(NSRange(location: 0, length: lineNS.length), .boundary)
                inHeaders = true
                return
            }

            if inHeaders {
                if let first = line.unicodeScalars.first, first != " ", first != "\t" {
                    let colon = lineNS.range(of: ":")
                    if colon.location != NSNotFound, colon.location > 0,
                       lineNS.substring(to: colon.location).allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }) {
                        add(NSRange(location: 0, length: colon.location + 1), .headerName)
                    }
                }
                for m in matches(encodedWord) { add(m.range, .encodedWord) }
                for m in matches(address) { add(m.range, .address) }
                for m in matches(authResult) {
                    let result = lineNS.substring(with: m.range(at: 1)).lowercased()
                    let style: Style
                    switch result {
                    case "pass", "bestguesspass": style = .pass
                    case "fail", "softfail", "hardfail", "permerror": style = .fail
                    default: style = .neutral
                    }
                    add(m.range, style)
                }
            } else {
                if isEncodedDataLine(lineNS) {
                    add(NSRange(location: 0, length: lineNS.length), .encodedData)
                    return
                }
                for m in matches(htmlTag) { add(m.range, .htmlTag) }
            }
        }
        return spans
    }

    /// A line that looks like base64 payload (long, no spaces, base64 alphabet only).
    private static func isEncodedDataLine(_ line: NSString) -> Bool {
        guard line.length >= 40 else { return false }
        for i in 0..<line.length {
            switch line.character(at: i) {
            case 65...90, 97...122, 48...57, 43, 47, 61: continue // A-Z a-z 0-9 + / =
            default: return false
            }
        }
        return true
    }
}
