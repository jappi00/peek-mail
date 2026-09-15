// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "PeekMail",
    platforms: [.macOS(.v14)],
    dependencies: [
        // Auto-updates; the only third-party dependency.
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0"),
    ],
    targets: [
        .target(name: "MailCore"),
        .executableTarget(
            name: "PeekMail",
            dependencies: ["MailCore", .product(name: "Sparkle", package: "Sparkle")]
        ),
        .executableTarget(name: "maildump", dependencies: ["MailCore"]),
    ]
)
