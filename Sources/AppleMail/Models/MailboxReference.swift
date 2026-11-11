//
//  MailboxReference.swift
//  AppleMail
//
//  Created by David Sherlock on 2026.
//

import Foundation

/// A mailbox, named the way Mail's scripting finds it: an account and a path.
///
/// `accountID` is Mail's own account identifier — the UUID AppleScript calls
/// `id of account`, which is also the host of the mailbox URL in the index
/// (verified on macOS 27: `imap://73AA…/Receipts` belongs to `account id
/// "73AA…"`). `nil` means **On My Mac**: local mailboxes have no account.
///
/// `path` is the full folder path, `/`-separated — `Work/Invoices`.
/// Mail resolves `mailbox "Work/Invoices" of account …` directly.
public struct MailboxReference: Sendable, Equatable, Hashable, Codable {

    /// Mail's account identifier, or `nil` for On My Mac.
    public let accountID: String?

    /// The folder path, e.g. `Work/Invoices`.
    public let path: String

    public init(accountID: String?, path: String) {
        self.accountID = accountID
        self.path = path
    }

    /// A mailbox under On My Mac.
    public static func onMyMac(_ path: String) -> MailboxReference {
        MailboxReference(accountID: nil, path: path)
    }

    /// Whether this is an On My Mac mailbox.
    public var isLocal: Bool { accountID == nil }

    /// The last component of the path — what Mail shows in the sidebar.
    public var leaf: String {
        path.split(separator: "/").last.map(String.init) ?? path
    }

    /// Everything above the leaf, or `nil` at the top level.
    public var parent: String? {
        let parts = path.split(separator: "/")
        return parts.count > 1 ? parts.dropLast().joined(separator: "/") : nil
    }

    /// `On My Mac · Inbox Test`, or the bare path for an account mailbox.
    public var described: String {
        isLocal ? "On My Mac · \(path)" : path
    }
}
