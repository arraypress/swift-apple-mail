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
    targets: [
        .target(name: "AppleMail"),
        .testTarget(name: "AppleMailTests", dependencies: ["AppleMail"]),
    ]
)

// Swift 7's import rule, today: a file must import every module whose members
// it uses, rather than leaning on another file's imports.
for target in package.targets where target.type != .system && target.type != .binary && target.type != .plugin {
    target.swiftSettings = (target.swiftSettings ?? []) + [.enableUpcomingFeature("MemberImportVisibility")]
}
