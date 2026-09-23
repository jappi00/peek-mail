import Observation
import WebKit

/// Searches the rendered message. WebKit's own find selects and scrolls to matches;
/// the match count comes from a script in an isolated content world (mail scripts stay disabled).
@MainActor
@Observable
final class MessageFinder: FindModel {
    var query = "" {
        didSet { if query != oldValue { Task { await search() } } }
    }
    private(set) var matchCount = 0
    private(set) var currentMatch = 0

    @ObservationIgnored private weak var webView: WKWebView?
    @ObservationIgnored private var generation = 0

    private static let countScript = """
        const text = (document.body ? document.body.innerText : "").toLocaleLowerCase();
        const needle = query.toLocaleLowerCase();
        if (!needle) { return 0; }
        let count = 0, index = 0;
        while ((index = text.indexOf(needle, index)) !== -1) { count++; index += needle.length; }
        return count;
        """

    func attach(_ webView: WKWebView) {
        self.webView = webView
    }

    /// Called when the message finished (re)loading, e.g. after "Load Images".
    func documentDidLoad() {
        if !query.isEmpty { Task { await search() } }
    }

    func next() {
        guard matchCount > 0 else { return }
        currentMatch = (currentMatch + 1) % matchCount
        Task { await find(backwards: false) }
    }

    func previous() {
        guard matchCount > 0 else { return }
        currentMatch = (currentMatch - 1 + matchCount) % matchCount
        Task { await find(backwards: true) }
    }

    private func search() async {
        generation += 1
        let searchGeneration = generation
        guard let webView else { return }
        _ = try? await webView.callAsyncJavaScript(
            "window.getSelection().removeAllRanges();", arguments: [:], in: nil, contentWorld: .defaultClient)
        currentMatch = 0
        guard !query.isEmpty else {
            matchCount = 0
            return
        }
        let result = try? await webView.callAsyncJavaScript(
            Self.countScript, arguments: ["query": query], in: nil, contentWorld: .defaultClient)
        guard searchGeneration == generation else { return } // a newer search started meanwhile
        matchCount = (result as? NSNumber)?.intValue ?? 0
        if matchCount > 0 { await find(backwards: false) }
    }

    private func find(backwards: Bool) async {
        guard let webView, !query.isEmpty else { return }
        let configuration = WKFindConfiguration()
        configuration.caseSensitive = false
        configuration.wraps = true
        configuration.backwards = backwards
        _ = try? await webView.find(query, configuration: configuration)
    }
}

extension MailWebView.Coordinator {
    /// Re-runs an active search once the message (re)loaded, e.g. after "Load Images".
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        (webView as? NonDropWebView)?.finder?.documentDidLoad()
    }
}
