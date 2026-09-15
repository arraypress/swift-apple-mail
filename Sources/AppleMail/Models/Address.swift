//
//  Address.swift
//  AppleMail
//
//  Created by David Sherlock on 2026.
//

import Foundation

/// Somebody an email came from or went to.
///
/// Two fields because a header carries two: `Ada Lovelace <ada@example.com>`
/// is a display name and an address, and they are independently useful —
/// grouping by address is right, showing the name is friendlier.
public struct Address: Sendable, Equatable, Codable, Hashable {

    /// The address itself, lowercased by the store.
    public let address: String

    /// The display name, when the sender set one.
    public let name: String?

    public init(address: String, name: String? = nil) {
        self.address = address
        // Mail keeps an empty comment rather than none; treat both as absent
        // so a caller never has to test for a blank string.
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.name = (trimmed?.isEmpty ?? true) ? nil : trimmed
    }

    /// `Ada Lovelace <ada@example.com>`, or the address alone.
    public var described: String {
        guard let name else { return address }
        return "\(name) <\(address)>"
    }

    /// The name if there is one, otherwise the address.
    public var shortName: String { name ?? address }

    /// The part after the `@`, lowercased — for grouping by organisation.
    public var domain: String {
        guard let at = address.lastIndex(of: "@") else { return "" }
        return String(address[address.index(after: at)...]).lowercased()
    }
}
