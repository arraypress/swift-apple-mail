//
//  Mailbox.swift
//  AppleMail
//
//  Created by David Sherlock on 2026.
//

import Foundation

/// A folder, in an account.
public struct Mailbox: Sendable, Equatable, Codable, Identifiable {

    public let id: Int64

    /// Mail's own URL for the folder, e.g. `imap://…/INBOX`.
    ///
    /// **Carries the account's address** in its user component for most
    /// accounts, which is why ``name`` and ``account`` exist: neither includes
    /// it, and a listing that printed the raw URL would put somebody's email
    /// address in every row of the output.
    public let url: String

    /// The folder's name, as Mail shows it: `INBOX`, `Sent Messages`.
    public let name: String

    /// Which account it belongs to — the host, not the address.
    public let account: String

    public let totalCount: Int
    public let unreadCount: Int

    public init(id: Int64, url: String, totalCount: Int = 0, unreadCount: Int = 0) {
        self.id = id
        self.url = url
        self.totalCount = totalCount
        self.unreadCount = unreadCount
        (self.account, self.name) = Self.split(url)
    }

    /// Splits a mailbox URL into an account and a folder path.
    ///
    /// `imap://ada%40example.com@imap.example.com/INBOX/Receipts` becomes
    /// `("imap.example.com", "INBOX/Receipts")`. The user component is dropped
    /// deliberately rather than kept and hidden later: a value that is never
    /// stored cannot leak into a log, a JSON payload or a bug report.
    static func split(_ url: String) -> (account: String, name: String) {
        guard let components = URLComponents(string: url) else { return ("", url) }
        let host = components.host ?? components.scheme ?? ""
        var path = components.path
        if path.hasPrefix("/") { path.removeFirst() }
        let name = path.removingPercentEncoding ?? path
        return (host, name.isEmpty ? (components.scheme ?? "") : name)
    }

    /// `imap.example.com · INBOX`.
    public var described: String {
        account.isEmpty ? name : "\(account) · \(name)"
    }

    /// Whether this is a folder mail arrives in, rather than one it leaves from.
    ///
    /// Used to keep `Sent`, `Drafts` and `Trash` out of answers about what
    /// somebody has received — a search for "everything from Ada" that returns
    /// your own replies to Ada is answering a different question.
    public var isIncoming: Bool {
        let leaf = name.split(separator: "/").last.map(String.init)?.lowercased() ?? ""
        return !["sent messages", "sent", "drafts", "trash", "deleted messages",
                 "junk", "spam", "archive.sent"].contains(leaf)
    }
}
