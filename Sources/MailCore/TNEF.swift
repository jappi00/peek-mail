import Foundation
import UniformTypeIdentifiers

/// Reader for Outlook's Transport Neutral Encapsulation Format (`winmail.dat`, `application/ms-tnef`).
/// Outlook and Exchange sometimes wrap a mail's formatted body and attachments in this format.
enum TNEF {
    struct Content {
        var htmlBody: String?
        var textBody: String?
        var attachments: [MailAttachment] = []
    }

    private static let signature: UInt32 = 0x223E_9F78

    // Attribute IDs (low 16 bits of the attribute tag).
    private static let attBody: UInt32 = 0x800C
    private static let attMAPIProps: UInt32 = 0x9003
    private static let attOemCodepage: UInt32 = 0x9007
    private static let attAttachRenddata: UInt32 = 0x9002
    private static let attAttachTitle: UInt32 = 0x8010
    private static let attAttachData: UInt32 = 0x800F
    private static let attAttachment: UInt32 = 0x9005

    static func isTNEF(_ data: [UInt8]) -> Bool {
        data.count >= 6 && CompoundFile.u32(data, 0) == signature
    }

    private struct PendingAttachment {
        var title: String?
        var data: [UInt8]?
        var properties: [UInt16: MAPIProperty] = [:]
    }

    static func parse(_ bytes: [UInt8]) -> Content? {
        guard isTNEF(bytes) else { return nil }
        var offset = 6 // signature (4) + legacy key (2)
        var codepage = String.Encoding.windowsCP1252
        var plainBody: [UInt8]?
        var messageProperties: [UInt16: MAPIProperty] = [:]
        var pending: [PendingAttachment] = []

        while offset + 9 <= bytes.count {
            let level = bytes[offset]
            let id = CompoundFile.u32(bytes, offset + 1) & 0xFFFF
            let length = Int(CompoundFile.u32(bytes, offset + 5))
            let start = offset + 9
            guard length >= 0, start + length + 2 <= bytes.count else { break }
            let value = Array(bytes[start..<(start + length)])
            offset = start + length + 2 // value + 16-bit checksum

            switch (level, id) {
            case (1, attOemCodepage):
                if value.count >= 4, let encoding = MSGParser.encoding(forWindowsCodepage: Int(CompoundFile.u32(value, 0))) {
                    codepage = encoding
                }
            case (1, attBody):
                plainBody = value
            case (1, attMAPIProps):
                messageProperties = mapiProperties(value)
            case (2, attAttachRenddata):
                pending.append(PendingAttachment()) // starts a new attachment
            case (2, attAttachTitle):
                if !pending.isEmpty { pending[pending.count - 1].title = cString(value, codepage) }
            case (2, attAttachData):
                if !pending.isEmpty { pending[pending.count - 1].data = value }
            case (2, attAttachment):
                if !pending.isEmpty { pending[pending.count - 1].properties = mapiProperties(value) }
            default:
                break
            }
        }

        var content = Content()

        // Body: HTML if present, else HTML encapsulated in compressed RTF, else plain text.
        if let html = messageProperties[0x1013] {
            let cpid = messageProperties[0x3FDE]?.int.flatMap(MSGParser.encoding(forWindowsCodepage:))
            content.htmlBody = html.string(codepage: cpid ?? .utf8)
        } else if let rtf = messageProperties[0x1009]?.binary, let decompressed = RTF.decompress(rtf) {
            content.htmlBody = RTF.extractHTML(decompressed)
        }
        content.textBody = messageProperties[0x1000]?.string(codepage: codepage)
            ?? plainBody.flatMap { cString($0, codepage) }

        for (index, attachment) in pending.enumerated() {
            let props = attachment.properties
            guard let data = attachment.data ?? props[0x3701]?.binary, !data.isEmpty else { continue }
            let filename = props[0x3707]?.string(codepage: codepage)
                ?? props[0x3704]?.string(codepage: codepage)
                ?? attachment.title
                ?? "attachment-\(index + 1)"
            let ext = (filename as NSString).pathExtension
            let mime = props[0x370E]?.string(codepage: codepage)
                ?? UTType(filenameExtension: ext)?.preferredMIMEType
                ?? "application/octet-stream"
            content.attachments.append(MailAttachment(
                filename: filename, mimeType: mime, data: Data(data),
                contentID: props[0x3712]?.string(codepage: codepage)))
        }

        let hasContent = content.htmlBody != nil || content.textBody?.trimmed.isEmpty == false || !content.attachments.isEmpty
        return hasContent ? content : nil
    }

    // MARK: - MAPI properties

    struct MAPIProperty {
        var type: UInt16
        var values: [[UInt8]]

        var binary: [UInt8]? {
            guard let value = values.first else { return nil }
            // Embedded objects (PT_OBJECT) start with a 16-byte interface ID.
            return type == 0x000D && value.count > 16 ? Array(value[16...]) : value
        }

        var int: Int? {
            guard let value = values.first, value.count >= 4 else { return nil }
            return Int(Int32(bitPattern: CompoundFile.u32(value, 0)))
        }

        func string(codepage: String.Encoding) -> String? {
            guard let value = values.first else { return nil }
            let text: String?
            switch type {
            case 0x001F: text = String(bytes: value, encoding: .utf16LittleEndian)
            case 0x001E: text = String(bytes: value, encoding: codepage) ?? String(bytes: value, encoding: .utf8)
            case 0x0102: text = String(bytes: value, encoding: codepage) ?? String(bytes: value, encoding: .windowsCP1252)
            default: text = nil
            }
            return text?.trimmingCharacters(in: CharacterSet(charactersIn: "\0")).nonEmpty
        }
    }

    private static func padded(_ length: Int) -> Int { (length + 3) & ~3 }

    static func mapiProperties(_ b: [UInt8]) -> [UInt16: MAPIProperty] {
        var properties: [UInt16: MAPIProperty] = [:]
        guard b.count >= 4 else { return properties }
        let count = Int(CompoundFile.u32(b, 0))
        var o = 4

        for _ in 0..<count {
            guard o + 4 <= b.count else { break }
            let type = CompoundFile.u16(b, o)
            let id = CompoundFile.u16(b, o + 2)
            o += 4

            if id >= 0x8000 { // named property: GUID + kind + (ID or name)
                guard o + 20 <= b.count else { break }
                o += 16
                let kind = CompoundFile.u32(b, o)
                o += 4
                if kind == 0 {
                    o += 4
                } else {
                    guard o + 4 <= b.count else { break }
                    o += 4 + padded(Int(CompoundFile.u32(b, o)))
                }
            }

            let isMultiValued = type & 0x1000 != 0
            let baseType = type & 0x0FFF
            var values: [[UInt8]] = []
            var fixedSize: Int?
            switch baseType {
            case 0x0002, 0x0003, 0x0004, 0x000A, 0x000B: fixedSize = 4 // short (padded), long, float, error, boolean
            case 0x0005, 0x0006, 0x0007, 0x0014, 0x0040: fixedSize = 8 // double, currency, apptime, int64, systime
            case 0x0048: fixedSize = 16 // CLSID
            default: fixedSize = nil
            }

            if let size = fixedSize {
                var n = 1
                if isMultiValued {
                    guard o + 4 <= b.count else { break }
                    n = Int(CompoundFile.u32(b, o))
                    o += 4
                }
                guard n >= 0, o + n * size <= b.count else { break }
                for _ in 0..<n {
                    values.append(Array(b[o..<(o + size)]))
                    o += size
                }
            } else if [0x001E, 0x001F, 0x0102, 0x000D].contains(baseType) {
                // Variable-length values are always preceded by a count, then length + padded data each.
                guard o + 4 <= b.count else { break }
                let n = Int(CompoundFile.u32(b, o))
                o += 4
                var complete = true
                for _ in 0..<max(n, 0) {
                    guard o + 4 <= b.count else { complete = false; break }
                    let length = Int(CompoundFile.u32(b, o))
                    o += 4
                    guard length >= 0, o + length <= b.count else { complete = false; break }
                    values.append(Array(b[o..<(o + length)]))
                    o += padded(length)
                }
                if !complete { break }
            } else {
                break // unknown type: stop rather than misread the rest
            }
            properties[id] = MAPIProperty(type: baseType, values: values)
        }
        return properties
    }

    private static func cString(_ bytes: [UInt8], _ encoding: String.Encoding) -> String? {
        let trimmed = bytes.prefix { $0 != 0 }
        return (String(bytes: trimmed, encoding: encoding) ?? String(bytes: trimmed, encoding: .windowsCP1252))?.nonEmpty
    }
}
