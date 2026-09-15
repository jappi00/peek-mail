import AppKit

/// Author, website and support details shown in the About panel and Help menu.
enum AppInfo {
    static let authorName = "Jan-Phillip Oesterling"
    static let authorEmail = "jp@oesterl.ing"
    static let supportEmail = "support@oesterl.ing"
    static let website = URL(string: "https://peekmail.oesterl.ing")!
    static let sourceCode = URL(string: "https://github.com/jappi00/peek-mail")!
    static let issues = URL(string: "https://github.com/jappi00/peek-mail/issues")!

    static var supportMail: URL {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let subject = "Peek Mail \(version)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return URL(string: "mailto:\(supportEmail)?subject=\(subject)")!
    }

    @MainActor
    static func showAboutPanel() {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineSpacing = 2
        let base: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: paragraph,
        ]
        let credits = NSMutableAttributedString()
        func add(_ text: String, link: URL? = nil) {
            var attributes = base
            if let link { attributes[.link] = link }
            credits.append(NSAttributedString(string: text, attributes: attributes))
        }

        add("Made by ")
        add(authorName, link: URL(string: "mailto:\(authorEmail)"))
        add("\n")
        add("peekmail.oesterl.ing", link: website)
        add("  ·  ")
        add("Source code", link: sourceCode)
        add("\nSupport: ")
        add(supportEmail, link: supportMail)

        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
        NSApp.activate()
    }
}
