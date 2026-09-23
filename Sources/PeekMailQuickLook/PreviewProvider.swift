import Foundation
import MailCore
import QuickLookUI
import UniformTypeIdentifiers

/// Quick Look preview (Space in Finder) for .eml and .msg files.
/// Runs sandboxed without network access, so remote images never load in previews.
@objc(PreviewProvider)
final class PreviewProvider: QLPreviewProvider, QLPreviewingController {
    func providePreview(for request: QLFilePreviewRequest) async throws -> QLPreviewReply {
        let data = try Data(contentsOf: request.fileURL)
        let message = try MailParser.parse(data: data)
        let html = MailDocument.standaloneHTML(for: message)

        let reply = QLPreviewReply(dataOfContentType: .html, contentSize: CGSize(width: 820, height: 1000)) { _ in
            Data(html.utf8)
        }
        reply.stringEncoding = .utf8
        reply.title = message.subject.isEmpty ? request.fileURL.lastPathComponent : message.subject
        return reply
    }
}
