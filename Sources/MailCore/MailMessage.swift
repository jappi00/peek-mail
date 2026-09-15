import Foundation

public struct MailAddress: Hashable, Sendable {
    public var name: String?
    public var email: String?

    public init(name: String?, email: String?) {
        self.name = name?.trimmed.nonEmpty
        self.email = email?.trimmed.nonEmpty
    }

    public var displayName: String { name ?? email ?? "Unknown" }

    public var formatted: String {
        if let name, let email, name != email { return "\(name) <\(email)>" }
        return displayName
    }
}

public struct MailAttachment: Identifiable, Hashable, Sendable {
    public var id = UUID()
    public var filename: String
    public var mimeType: String
    public var data: Data
    public var contentID: String?

    public init(filename: String, mimeType: String, data: Data, contentID: String?) {
        self.filename = filename
        self.mimeType = mimeType
        self.data = data
        self.contentID = contentID
    }
}

public struct MailHeader: Hashable, Sendable {
    public var name: String
    /// Value as it appears in the file (unfolded).
    public var value: String
    /// Value with RFC 2047 encoded words decoded.
    public var decodedValue: String

    public init(name: String, value: String) {
        self.name = name
        self.value = value
        self.decodedValue = EMLParser.decodeWords(value)
    }
}

public struct MailMessage: Sendable {
    public var subject = ""
    /// Top-level headers in original order (for .msg: parsed from the transport headers, if present).
    public var headers: [MailHeader] = []
    /// Raw transport header block stored in .msg files.
    public var transportHeaders: String?
    public var from: MailAddress?
    public var to: [MailAddress] = []
    public var cc: [MailAddress] = []
    public var bcc: [MailAddress] = []
    public var date: Date?
    public var htmlBody: String?
    public var textBody: String?
    public var attachments: [MailAttachment] = []

    public init() {}

    /// HTML body with `cid:` references replaced by inline data URIs.
    public var resolvedHTML: String? {
        guard var html = htmlBody else { return nil }
        for att in attachments {
            guard let cid = att.contentID, html.range(of: "cid:\(cid)", options: .caseInsensitive) != nil else { continue }
            let uri = "data:\(att.mimeType);base64,\(att.data.base64EncodedString())"
            html = html.replacingOccurrences(of: "cid:\(cid)", with: uri, options: .caseInsensitive)
        }
        return html
    }

    /// Attachments that are not just images embedded in the HTML body.
    public var visibleAttachments: [MailAttachment] {
        attachments.filter { att in
            guard let cid = att.contentID, let html = htmlBody else { return true }
            return html.range(of: "cid:\(cid)", options: .caseInsensitive) == nil
        }
    }
}

public enum MailParserError: LocalizedError {
    case invalidFile(String)

    public var errorDescription: String? {
        switch self {
        case .invalidFile(let reason): return reason
        }
    }
}

public enum MailParser {
    static let oleSignature: [UInt8] = [0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1]

    public static func parse(data: Data) throws -> MailMessage {
        if data.starts(with: oleSignature) {
            return try MSGParser.parse(data)
        }
        return EMLParser.parse(data)
    }
}

extension StringProtocol {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
