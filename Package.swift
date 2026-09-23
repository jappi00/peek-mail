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
        // Quick Look extension. Built as an executable whose entry point is NSExtensionMain;
        // build.sh wraps it into PeekMailQuickLook.appex inside the app.
        .executableTarget(
            name: "PeekMailQuickLook",
            dependencies: ["MailCore"],
            swiftSettings: [.unsafeFlags(["-parse-as-library", "-application-extension"])],
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-e", "-Xlinker", "_NSExtensionMain", "-Xlinker", "-application_extension"]),
                .linkedFramework("QuickLookUI"),
            ]
        ),
        .executableTarget(name: "maildump", dependencies: ["MailCore"]),
    ]
)
