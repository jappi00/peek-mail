// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "PeekMail",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "MailCore"),
        .executableTarget(name: "PeekMail", dependencies: ["MailCore"]),
        .executableTarget(name: "maildump", dependencies: ["MailCore"]),
    ]
)
