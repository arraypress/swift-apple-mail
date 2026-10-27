// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "swift-apple-mail",
    platforms: [
        // macOS only, and not by choice: Mail's message store exists nowhere
        // else. There is no iOS equivalent to read, with or without
        // permission.
        .macOS(.v14)
    ],
    products: [
        .library(name: "AppleMail", targets: ["AppleMail"]),
    ],
    dependencies: [
        // Opening the Envelope Index read-only and running queries over it.
        .package(url: "https://github.com/arraypress/swift-sqlite-reader.git", from: "0.2.0"),
    ],
    targets: [
        .target(name: "AppleMail", dependencies: [
            .product(name: "SQLiteReader", package: "swift-sqlite-reader"),
        ]),
        .testTarget(name: "AppleMailTests", dependencies: [
            "AppleMail",
            .product(name: "SQLiteReader", package: "swift-sqlite-reader"),
        ]),
    ]
)

// Swift 7's import rule, today: a file must import every module whose members
// it uses, rather than leaning on another file's imports.
for target in package.targets where target.type != .system && target.type != .binary && target.type != .plugin {
    target.swiftSettings = (target.swiftSettings ?? []) + [.enableUpcomingFeature("MemberImportVisibility")]
}
