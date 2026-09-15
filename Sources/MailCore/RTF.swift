import Foundation

/// Compressed RTF (MS-OXRTFCP) decompression and HTML de-encapsulation (MS-OXRTFEX).
enum RTF {
    private static let prebuffer = Array(
        "{\\rtf1\\ansi\\mac\\deff0\\deftab720{\\fonttbl;}{\\f0\\fnil \\froman \\fswiss \\fmodern \\fscript \\fdecor MS Sans SerifSymbolArialTimes New RomanCourier{\\colortbl\\red0\\green0\\blue0\r\n\\par \\pard\\plain\\f0\\fs20\\b\\i\\u\\tab\\tx".utf8)

    static func decompress(_ b: [UInt8]) -> [UInt8]? {
        guard b.count >= 16 else { return nil }
        let compSize = Int(CompoundFile.u32(b, 0))
        let rawSize = Int(CompoundFile.u32(b, 4))
        let type = CompoundFile.u32(b, 8)

        if type == 0x414C_454D { // "MELA": uncompressed
            return Array(b[16..<min(b.count, 16 + rawSize)])
        }
        guard type == 0x7546_5A4C else { return nil } // "LZFu"

        var dict = [UInt8](repeating: 0, count: 4096)
        dict.replaceSubrange(0..<prebuffer.count, with: prebuffer)
        var writePos = prebuffer.count
        var out: [UInt8] = []
        out.reserveCapacity(rawSize)
        var i = 16
        let end = min(b.count, compSize + 4)

        outer: while i < end {
            let control = b[i]
            i += 1
            for bit in 0..<8 {
                guard i < end else { break outer }
                if control & (1 << bit) == 0 {
                    let c = b[i]
                    i += 1
                    out.append(c)
                    dict[writePos] = c
                    writePos = (writePos + 1) & 0xFFF
                } else {
                    guard i + 1 < end else { break outer }
                    let token = Int(b[i]) << 8 | Int(b[i + 1])
                    i += 2
                    let offset = token >> 4
                    let length = (token & 0xF) + 2
                    if offset == writePos { break outer }
                    for k in 0..<length {
                        let c = dict[(offset + k) & 0xFFF]
                        out.append(c)
                        dict[writePos] = c
                        writePos = (writePos + 1) & 0xFFF
                    }
                }
            }
        }
        return out
    }

    /// Extracts HTML encapsulated in RTF (`\fromhtml1`). Returns nil for native RTF.
    static func extractHTML(_ rtf: [UInt8]) -> String? {
        guard let head = String(bytes: rtf.prefix(1024), encoding: .isoLatin1), head.contains("\\fromhtml") else { return nil }

        struct State {
            var suppressed = false
            var htmlTag = false
            var skip = false
            var unicodeSkip = 1
        }

        let skipDestinations: Set<String> = ["fonttbl", "colortbl", "stylesheet", "info", "pict", "object", "header", "footer", "mhtmltag"]
        var stack: [State] = []
        var state = State()
        var out = ""
        var pending: [UInt8] = []
        var encoding = String.Encoding.windowsCP1252
        var fallbackToSkip = 0
        var atGroupStart = false
        let n = rtf.count
        var i = 0

        func flush() {
            guard !pending.isEmpty else { return }
            out += String(bytes: pending, encoding: encoding) ?? String(bytes: pending, encoding: .isoLatin1) ?? ""
            pending.removeAll(keepingCapacity: true)
        }
        func emitting() -> Bool { !state.skip && (state.htmlTag || !state.suppressed) }
        func emit(_ byte: UInt8) {
            if fallbackToSkip > 0 { fallbackToSkip -= 1; return }
            if emitting() { pending.append(byte) }
        }
        func isLetter(_ c: UInt8) -> Bool { (c >= 97 && c <= 122) || (c >= 65 && c <= 90) }
        func isDigit(_ c: UInt8) -> Bool { c >= 48 && c <= 57 }

        while i < n {
            let c = rtf[i]
            switch c {
            case UInt8(ascii: "{"):
                stack.append(state)
                atGroupStart = true
                i += 1
            case UInt8(ascii: "}"):
                if let previous = stack.popLast() { state = previous }
                atGroupStart = false
                i += 1
            case UInt8(ascii: "\\"):
                guard i + 1 < n else { i += 1; continue }
                let next = rtf[i + 1]
                if isLetter(next) {
                    var j = i + 1
                    while j < n, isLetter(rtf[j]) { j += 1 }
                    let word = String(bytes: rtf[(i + 1)..<j], encoding: .ascii) ?? ""
                    var param: Int?
                    var k = j
                    if k < n, rtf[k] == UInt8(ascii: "-") || isDigit(rtf[k]) {
                        k += 1
                        while k < n, isDigit(rtf[k]) { k += 1 }
                        param = Int(String(bytes: rtf[j..<k], encoding: .ascii) ?? "")
                    }
                    if k < n, rtf[k] == UInt8(ascii: " ") { k += 1 }
                    i = k

                    let groupStart = atGroupStart
                    atGroupStart = false
                    switch word {
                    case "htmltag":
                        state.htmlTag = true
                        state.skip = false
                    case "htmlrtf":
                        state.suppressed = (param ?? 1) != 0
                    case "par", "line":
                        if emitting() { pending += [13, 10] }
                    case "tab":
                        if emitting() { pending.append(9) }
                    case "ansicpg":
                        flush()
                        if let p = param, let enc = MSGParser.encoding(forWindowsCodepage: p) { encoding = enc }
                    case "uc":
                        state.unicodeSkip = param ?? 1
                    case "u":
                        if emitting(), var value = param {
                            if value < 0 { value += 65536 }
                            flush()
                            if let scalar = Unicode.Scalar(value) { out.unicodeScalars.append(scalar) }
                        }
                        fallbackToSkip = state.unicodeSkip
                    default:
                        if groupStart || state.skip, skipDestinations.contains(word) { state.skip = true }
                    }
                } else {
                    switch next {
                    case UInt8(ascii: "'"):
                        if i + 3 < n, let h = EMLParser.hexValue(rtf[i + 2]), let l = EMLParser.hexValue(rtf[i + 3]) {
                            emit(h << 4 | l)
                        }
                        i += 4
                        continue
                    case UInt8(ascii: "*"):
                        state.skip = true
                        i += 2
                        continue // keep atGroupStart so \*\htmltag is recognised
                    case UInt8(ascii: "\\"), UInt8(ascii: "{"), UInt8(ascii: "}"):
                        emit(next)
                    case UInt8(ascii: "~"):
                        emit(0xA0)
                    case UInt8(ascii: "_"):
                        emit(UInt8(ascii: "-"))
                    case 10, 13:
                        if emitting() { pending += [13, 10] }
                    default:
                        break
                    }
                    atGroupStart = false
                    i += 2
                }
            case 10, 13:
                i += 1
            default:
                atGroupStart = false
                emit(c)
                i += 1
            }
        }
        flush()
        return out.trimmed.nonEmpty
    }
}
