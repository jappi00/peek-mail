import Foundation
import UniformTypeIdentifiers

/// A storage (message, recipient or attachment) inside an Outlook .msg file.
private struct MSGStorage {
    let file: CompoundFile
    let index: Int
    let propertyHeaderSize: Int
    let children: [String: Int]

    init(file: CompoundFile, index: Int, propertyHeaderSize: Int) {
        self.file = file
        self.index = index
        self.propertyHeaderSize = propertyHeaderSize
        var map: [String: Int] = [:]
        for child in file.children(of: index) {
            map[file.entries[child].name.uppercased()] = child
        }
        children = map
    }

    func stream(_ name: String) -> [UInt8]? {
        children[name.uppercased()].map { file.data(of: $0) }
    }

    func substorages(prefix: String) -> [Int] {
        children.filter { $0.key.hasPrefix(prefix.uppercased()) }.sorted { $0.key < $1.key }.map(\.value)
    }

    private func tagName(_ tag: Int, _ type: String) -> String {
        "__substg1.0_" + String(format: "%04X", tag) + type
    }

    func string(_ tag: Int, codepage: String.Encoding = .windowsCP1252) -> String? {
        if let b = stream(tagName(tag, "001F")) {
            return String(bytes: b, encoding: .utf16LittleEndian)?.trimmingCharacters(in: CharacterSet(charactersIn: "\0")).nonEmpty
        }
        if let b = stream(tagName(tag, "001E")) {
            let s = String(bytes: b, encoding: .utf8) ?? String(bytes: b, encoding: codepage)
            return s?.trimmingCharacters(in: CharacterSet(charactersIn: "\0")).nonEmpty
        }
        return nil
    }

    func binary(_ tag: Int) -> [UInt8]? {
        stream(tagName(tag, "0102"))
    }

    /// Fixed-size property value (8 bytes) from the `__properties_version1.0` stream.
    func fixed(_ tag: Int) -> [UInt8]? {
        guard let p = stream("__properties_version1.0") else { return nil }
        var off = propertyHeaderSize
        while off + 16 <= p.count {
            if Int(CompoundFile.u32(p, off) >> 16) == tag {
                return Array(p[(off + 8)..<(off + 16)])
            }
            off += 16
        }
        return nil
    }

    func int(_ tag: Int) -> Int? {
        fixed(tag).map { Int(Int32(bitPattern: CompoundFile.u32($0, 0))) }
    }

    func time(_ tag: Int) -> Date? {
        guard let v = fixed(tag) else { return nil }
        let ticks = UInt64(CompoundFile.u32(v, 0)) | UInt64(CompoundFile.u32(v, 4)) << 32
        guard ticks > 0 else { return nil }
        return Date(timeIntervalSince1970: Double(ticks) / 10_000_000 - 11_644_473_600)
    }
}

enum MSGParser {
    static func parse(_ data: Data) throws -> MailMessage {
        let file = try CompoundFile(data)
        let root = MSGStorage(file: file, index: 0, propertyHeaderSize: 32)
        let codepage = root.int(0x3FFD).flatMap(encoding(forWindowsCodepage:)) ?? .windowsCP1252
        var msg = MailMessage()

        msg.subject = root.string(0x0037, codepage: codepage) ?? ""

        let senderName = root.string(0x0C1A, codepage: codepage) ?? root.string(0x0042, codepage: codepage)
        let senderEmail = [0x5D01, 0x0C1F, 0x0065, 0x5D02]
            .compactMap { root.string($0, codepage: codepage) }
            .first { $0.contains("@") }
        if senderName != nil || senderEmail != nil {
            msg.from = MailAddress(name: senderName, email: senderEmail)
        }

        for index in root.substorages(prefix: "__recip_version1.0_") {
            let r = MSGStorage(file: file, index: index, propertyHeaderSize: 8)
            let email = [0x39FE, 0x3003].compactMap { r.string($0, codepage: codepage) }.first { $0.contains("@") }
            let address = MailAddress(name: r.string(0x3001, codepage: codepage), email: email)
            switch r.int(0x0C15) {
            case 2: msg.cc.append(address)
            case 3: msg.bcc.append(address)
            default: msg.to.append(address)
            }
        }
        if msg.to.isEmpty, let display = root.string(0x0E04, codepage: codepage) {
            msg.to = display.split(separator: ";").map { MailAddress(name: String($0), email: nil) }
        }
        if msg.cc.isEmpty, let display = root.string(0x0E03, codepage: codepage) {
            msg.cc = display.split(separator: ";").map { MailAddress(name: String($0), email: nil) }
        }

        msg.date = root.time(0x0039) ?? root.time(0x0E06)
        if let transport = root.string(0x007D, codepage: codepage) {
            let part = MIMEPart(Array((transport + "\r\n\r\n").utf8))
            msg.transportHeaders = transport
            msg.headers = part.headers.map { MailHeader(name: $0.name, value: $0.value) }
            if msg.date == nil { msg.date = EMLParser.parseDate(part.header("date")) }
        }

        msg.textBody = root.string(0x1000, codepage: codepage)
        if let html = root.binary(0x1013) {
            let enc = root.int(0x3FDE).flatMap(encoding(forWindowsCodepage:))
            msg.htmlBody = enc.flatMap { String(bytes: html, encoding: $0) }
                ?? String(bytes: html, encoding: .utf8)
                ?? String(bytes: html, encoding: .windowsCP1252)
        } else if let html = root.string(0x1013, codepage: codepage) {
            msg.htmlBody = html
        } else if let compressed = root.binary(0x1009),
                  let rtf = RTF.decompress(compressed),
                  let html = RTF.extractHTML(rtf) {
            msg.htmlBody = html
        }

        for index in root.substorages(prefix: "__attach_version1.0_") {
            let a = MSGStorage(file: file, index: index, propertyHeaderSize: 8)
            guard let bytes = a.binary(0x3701) else { continue }
            let filename = a.string(0x3707, codepage: codepage) ?? a.string(0x3704, codepage: codepage)
                ?? a.string(0x3001, codepage: codepage) ?? "attachment-\(msg.attachments.count + 1)"
            let ext = (filename as NSString).pathExtension
            let mime = a.string(0x370E, codepage: codepage)
                ?? UTType(filenameExtension: ext)?.preferredMIMEType
                ?? "application/octet-stream"
            msg.attachments.append(MailAttachment(
                filename: filename, mimeType: mime, data: Data(bytes),
                contentID: a.string(0x3712, codepage: codepage)))
        }

        return msg
    }

    static func encoding(forWindowsCodepage cp: Int) -> String.Encoding? {
        if cp == 65001 { return .utf8 }
        let cf = CFStringConvertWindowsCodepageToEncoding(UInt32(cp))
        guard cf != kCFStringEncodingInvalidId else { return nil }
        return String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cf))
    }
}
