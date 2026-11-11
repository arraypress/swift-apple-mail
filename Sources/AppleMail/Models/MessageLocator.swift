//
//  MessageLocator.swift
//  AppleMail
//
//  Created by David Sherlock on 2026.
//

import Foundation

/// Where Mail's scripting can find one message: its mailbox and its
/// `Message-ID`.
///
/// Not the index row id. That id is this Mac's, and it CHANGES when a message
/// moves (measured: a message moved to a new folder came back with a new id). The `Message-ID` header travels with the message, so a locator
/// built before a move still names the same letter afterwards.
public struct MessageLocator: Sendable, Equatable, Hashable, Codable {

    /// The `Message-ID` **without** angle brackets — the form Mail's
    /// `message id` property holds. The index stores `<…>`; Mail matches only
    /// the bare value (measured on macOS 27: bracketed 0 matches, bare 1).
    public let messageID: String

    /// The mailbox it is in.
    public let mailbox: MailboxReference

    public init(messageID: String, mailbox: MailboxReference) {
        self.messageID = MessageIDs.bare(messageID)
        self.mailbox = mailbox
    }
}
