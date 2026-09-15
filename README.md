# Peek Mail

A small, native macOS app for viewing exported emails. Drop in `.eml` or Outlook `.msg` files and read them the way they were meant to look, with no mail account, no Outlook and no setup.

Built with SwiftUI and zero third-party dependencies.

## Features

- **Opens `.eml` and `.msg` files.** Drag them onto the window or Dock icon, use <kbd>⌘O</kbd>, or double-click them in Finder (several files at once work too).
- **Rendered messages.** HTML mails render with inline images; plain-text mails get clickable links. Attached emails open right inside the viewer.
- **History sidebar.** Every opened mail is kept with sender, subject and date, with search. Re-opening the same file jumps back to its entry instead of adding a duplicate.
- **Privacy by default.** Remote images, stylesheets and tracking pixels are blocked until you click *Load Images*. JavaScript in mails is disabled.
- **Clickable addresses.** Click a sender or recipient to see the full address, copy it, or start a new email.
- **Attachments.** Open them with a click or save them anywhere.
- **Debugging tools.**
  - *Headers* view with every header in original order and decoded values for `=?utf-8?…?=` words.
  - *Source* view with the raw `.eml` source (or extracted data for binary `.msg` files).
  - Syntax highlighting for header names, SPF/DKIM/DMARC results, addresses, MIME boundaries, base64 data and HTML tags.
  - Search with match highlighting and <kbd>⌘F</kbd>.

## Requirements

- macOS 14 Sonoma or later
- Swift 5.10 or later, either with Xcode or just the Command Line Tools (`xcode-select --install`)

## Build & install

```bash
git clone https://github.com/jappi00/peek-mail.git
cd peek-mail
./build.sh            # builds "build/Peek Mail.app"
./build.sh --install  # builds and copies it to /Applications
```

The build script compiles a release build, assembles the app bundle, generates the app icon and signs the app ad hoc. Builds made on your own Mac run without Gatekeeper warnings.

### Open `.eml` files with Peek Mail by default

Peek Mail registers itself for `.eml` and `.msg`, but Apple Mail usually stays the default for `.eml`. To change that, right-click an `.eml` file → **Get Info** → **Open with:** *Peek Mail* → **Change All…**

## Privacy

- Everything happens locally. Peek Mail makes no network requests of its own and collects no data.
- To keep the history working after you move or delete the original files, Peek Mail stores a copy of every opened mail in `~/Library/Application Support/PeekMail`. **File → Clear History…** or the *Clear All* button deletes them.
- Remote content in HTML mails is blocked until you allow it for that message.

## Project structure

```
Sources/
├── MailCore/            Parsing library (Foundation only)
│   ├── EMLParser.swift      MIME, encoded words, charsets, RFC 2231 parameters
│   ├── CompoundFile.swift   OLE2 / Compound File Binary reader
│   ├── MSGParser.swift      Outlook .msg properties, recipients, attachments
│   ├── RTF.swift            Compressed RTF + HTML de-encapsulation
│   ├── MailSource.swift     Source text for the debug view
│   └── SourceHighlighter.swift
├── PeekMail/            The SwiftUI app
└── maildump/            CLI that prints what the parser extracts
Resources/Info.plist     Bundle metadata and document types
Scripts/make-icon.swift  Renders the app icon
build.sh                 Builds the .app bundle
```

To debug parsing without the app:

```bash
swift run maildump path/to/mail.eml path/to/mail.msg
```

## Known limitations

- `winmail.dat` (TNEF) attachments aren't unpacked yet.
- S/MIME signed or encrypted mails show the `smime.p7m` part as an attachment.
- Emails attached inside `.msg` files are skipped.
- `.msg` files that store their body only as RTF are supported, but this path has seen little real-world testing.

Bug reports with (anonymized) sample files are very welcome.

## Contributing

Issues and pull requests are welcome. Please keep the project dependency-free and run `swift build` before opening a PR.

## License

[MIT](LICENSE) © 2026 Jan-Phillip Oesterling
