//
//  FlagColor.swift
//  AppleMail
//
//  Created by David Sherlock on 2026.
//

import Foundation

/// Mail's seven flag colours, in the order of its `flag index` (0–6).
///
/// Measured on macOS 27: setting `flag index` to one of these flags the
/// message in that colour; setting it to -1 removes the flag.
public enum FlagColor: Int, Sendable, Equatable, Codable, CaseIterable {
    case red = 0
    case orange = 1
    case yellow = 2
    case green = 3
    case blue = 4
    case purple = 5
    case gray = 6

    /// The name, as the CLI and JSON spell it.
    public var name: String {
        switch self {
        case .red: "red"
        case .orange: "orange"
        case .yellow: "yellow"
        case .green: "green"
        case .blue: "blue"
        case .purple: "purple"
        case .gray: "gray"
        }
    }

    /// A colour by name, accepting `grey` too.
    public init?(name: String) {
        let lowered = name.lowercased()
        guard let match = Self.allCases.first(where: { $0.name == lowered || (lowered == "grey" && $0 == .gray) })
        else { return nil }
        self = match
    }
}
