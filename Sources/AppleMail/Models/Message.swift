//
//  Message.swift
//  AppleMail
//
//  Created by David Sherlock on 2026.
//

import Foundation

/// One message, as the index knows it.
///
/// The envelope, not the letter. Everything here comes from Mail's own index
/// and is available for **every** message, including the ones whose bodies are
/// still on the server — which is most of an IMAP account. The body is fetched
/// separately, and may not exist locally at all; see ``MessageBody``.
public struct Message: Sendable, Equatable, Codable, Identifiable {

    /// Mail's row identifier. Also names the message's file on disk.
    public let id: Int64

    /// The `Message-ID` header, which survives across machines.
    ///
    /// Unlike ``id``, this is the same on every device and in every archive,
    /// so it is what to record if a reference has to outlive this Mac.
    public let messageID: String?

    public let subject: String
    public let sender: Address

    /// Everyone on the `To` and `Cc` lines.
    public let recipients: [Recipient]

    /// When the sender says they sent it.
    public let sentAt: Date

    /// When this Mac received it. The one to sort by — a sender's clock can
    /// say anything, and some say 1970.
    public let receivedAt: Date

    /// Which mailbox holds it.
    public let mailbox: String

    /// The thread this belongs to, as Mail groups them.
    public let conversationID: Int64

    public let isRead: Bool
    public let isFlagged: Bool

    /// Size in bytes, as the server reported it.
    public let size: Int

    /// Attachment filenames. The bytes live in the message file.
    public let attachmentNames: [String]

    public init(
        id: Int64,
        messageID: String? = nil,
        subject: String,
        sender: Address,
        recipients: [Recipient] = [],
        sentAt: Date,
        receivedAt: Date,
        mailbox: String,
        conversationID: Int64 = 0,
        isRead: Bool = true,
        isFlagged: Bool = false,
        size: Int = 0,
        attachmentNames: [String] = []
    ) {
        self.id = id
        self.messageID = messageID
        self.subject = subject
        self.sender = sender
        self.recipients = recipients
        self.sentAt = sentAt
        self.receivedAt = receivedAt
        self.mailbox = mailbox
        self.conversationID = conversationID
        self.isRead = isRead
        self.isFlagged = isFlagged
        self.size = size
        self.attachmentNames = attachmentNames
    }

    /// Whether anything is attached.
    public var hasAttachments: Bool { !attachmentNames.isEmpty }

    /// A subject fit to print, for the many messages that have none.
    public var displaySubject: String {
        subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "(no subject)"
            : subject
    }

    /// Everyone on the `To` line.
    public var to: [Address] { recipients.filter { $0.kind == .to }.map(\.address) }

    /// Everyone copied.
    public var cc: [Address] { recipients.filter { $0.kind == .cc }.map(\.address) }
}

/// An address with the header it appeared on.
public struct Recipient: Sendable, Equatable, Codable {

    public let address: Address
    public let kind: RecipientKind

    public init(address: Address, kind: RecipientKind) {
        self.address = address
        self.kind = kind
    }
}
