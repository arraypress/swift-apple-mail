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
