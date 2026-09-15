//
//  RecipientKind.swift
//  AppleMail
//
//  Created by David Sherlock on 2026.
//

import Foundation

/// Which header a recipient came from.
///
/// The raw values are Mail's own, measured against a real index: `to` is 0 and
/// `cc` is 1. `bcc` is 3 in the schema but never appears in received mail —
/// the whole point of a blind copy is that the recipient list does not carry
/// it — so it shows up only on messages you sent.
public enum RecipientKind: Int, Sendable, Equatable, Codable, CaseIterable {

    case to = 0
    case cc = 1
    case bcc = 3

    /// The header this came from, lowercased.
    public var label: String {
        switch self {
        case .to: "to"
        case .cc: "cc"
        case .bcc: "bcc"
        }
    }
}
