import AppKit
import MailCore
import UniformTypeIdentifiers
import WebKit

/// Prints a message or exports it as a paginated PDF, with its header above the body.
/// Renders the standalone document in an offscreen web view that may only load that document.
@MainActor
final class MailPrinter: NSObject, WKNavigationDelegate {
    /// Keeps running print jobs alive until they finish.
    private static var running: [MailPrinter] = []

    private let window: NSWindow
    private let webView: WKWebView
    private let exportURL: URL?
    private let jobTitle: String

    /// Prints (⌘P) or exports (⇧⌘E) the message selected in the history.
    static func printSelection(exportAsPDF: Bool) {
        let store = HistoryStore.shared
        guard let item = store.selectedItem, let message = store.cachedMessage(for: item) else {
            NSSound.beep()
            return
        }
        let title = message.subject.isEmpty ? (item.fileName as NSString).deletingPathExtension : message.subject

        var exportURL: URL?
        if exportAsPDF {
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.pdf]
            panel.canCreateDirectories = true
            panel.nameFieldStringValue = safeFilename(title) + ".pdf"
            guard panel.runModal() == .OK, let url = panel.url else { return }
            exportURL = url
        }

        let printer = MailPrinter(exportURL: exportURL, jobTitle: title)
        running.append(printer)
        let html = MailDocument.standaloneHTML(for: message, allowRemoteContent: store.remoteContentAllowed.contains(item.id))
        printer.webView.loadHTMLString(html, baseURL: nil)
    }

    private init(exportURL: URL?, jobTitle: String) {
        self.exportURL = exportURL
        self.jobTitle = jobTitle
        window = NSWindow(contentRect: NSRect(x: -10_000, y: -10_000, width: 800, height: 1000),
                          styleMask: .borderless, backing: .buffered, defer: false)
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        webView = WKWebView(frame: window.contentView!.bounds, configuration: configuration)
        super.init()
        window.contentView!.addSubview(webView)
        webView.navigationDelegate = self
    }

    // Only the generated document may load; no redirects, frames or form submissions.
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
        let isDocument = navigationAction.request.url?.scheme?.lowercased() == "about"
            && (navigationAction.targetFrame?.isMainFrame ?? false)
        decisionHandler(isDocument ? .allow : .cancel)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Give inline images a moment to lay out before paginating.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self.runPrintOperation() }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finish()
    }

    private func runPrintOperation() {
        let info: NSPrintInfo
        if let exportURL {
            info = NSPrintInfo(dictionary: [.jobSavingURL: exportURL])
            info.jobDisposition = .save
        } else {
            info = (NSPrintInfo.shared.copy() as? NSPrintInfo) ?? NSPrintInfo()
        }
        info.horizontalPagination = .fit
        info.verticalPagination = .automatic
        info.isVerticallyCentered = false
        info.topMargin = 36
        info.bottomMargin = 36
        info.leftMargin = 36
        info.rightMargin = 36

        let operation = webView.printOperation(with: info)
        operation.jobTitle = jobTitle
        operation.showsPrintPanel = exportURL == nil
        operation.showsProgressPanel = exportURL == nil
        operation.view?.frame = webView.bounds
        let parent = NSApp.keyWindow ?? NSApp.mainWindow ?? window
        operation.runModal(for: parent, delegate: self,
                           didRun: #selector(printOperationDidRun(_:success:contextInfo:)), contextInfo: nil)
    }

    @objc private func printOperationDidRun(_ operation: NSPrintOperation, success: Bool, contextInfo: UnsafeMutableRawPointer?) {
        finish()
    }

    private func finish() {
        Self.running.removeAll { $0 === self }
    }

    private static func safeFilename(_ title: String) -> String {
        let cleaned = title.components(separatedBy: CharacterSet(charactersIn: "/:\\?%*|\"<>")).joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Mail" : String(cleaned.prefix(120))
    }
}
