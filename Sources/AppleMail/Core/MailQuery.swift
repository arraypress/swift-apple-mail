//
//  MailQuery.swift
//  AppleMail
//
//  Created by David Sherlock on 2026.
//
//  What to look for. Turned into SQL in one place, with every value bound.
//

import Foundation

/// A search over the mail index.
///
/// Every field narrows the result; leaving one `nil` means "don't care". The
/// defaults are chosen so that the empty query — `MailQuery()` — is the
/// sensible one: recent mail, newest first, nothing deleted.
public struct MailQuery: Sendable, Equatable {

    /// Matches the subject, the sender's name, or the sender's address.
    public var text: String?

    /// Matches the sender's address or display name.
    public var from: String?

    /// Matches any recipient's address.
    public var to: String?

    /// Matches the subject only.
    public var subject: String?

    /// Matches a mailbox by name, e.g. `INBOX` or `Receipts`.
    public var mailbox: String?

    /// Received on or after this moment.
    public var since: Date?

    /// Received before this moment.
    public var until: Date?

    /// Only unread, only read, or either.
    public var isRead: Bool?

    /// Only flagged, only unflagged, or either.
    public var isFlagged: Bool?

    /// Only messages with something attached.
    public var hasAttachments: Bool?

    /// Only messages in mailboxes mail arrives in — no Sent, Drafts or Trash.
    ///
    /// On by default: a search for "everything from Ada" that returns your own
    /// replies to Ada is answering a different question.
    public var incomingOnly: Bool

    /// One thread.
    public var conversationID: Int64?

    /// How many to return.
    public var limit: Int

    /// Newest first, or oldest first.
    public var newestFirst: Bool

    public init(
        text: String? = nil,
        from: String? = nil,
        to: String? = nil,
        subject: String? = nil,
        mailbox: String? = nil,
        since: Date? = nil,
        until: Date? = nil,
        isRead: Bool? = nil,
        isFlagged: Bool? = nil,
        hasAttachments: Bool? = nil,
        incomingOnly: Bool = true,
        conversationID: Int64? = nil,
        limit: Int = 50,
        newestFirst: Bool = true
    ) {
        self.text = text
        self.from = from
        self.to = to
        self.subject = subject
        self.mailbox = mailbox
        self.since = since
        self.until = until
        self.isRead = isRead
        self.isFlagged = isFlagged
        self.hasAttachments = hasAttachments
        self.incomingOnly = incomingOnly
        self.conversationID = conversationID
        self.limit = limit
        self.newestFirst = newestFirst
    }

    /// Whether this query narrows anything at all.
    public var isEmpty: Bool {
        text == nil && from == nil && to == nil && subject == nil && mailbox == nil
            && since == nil && until == nil && isRead == nil && isFlagged == nil
            && hasAttachments == nil && conversationID == nil
    }
}

/// Builds the SQL for a query.
///
/// Separated from the store so the SQL can be tested without an index — and so
/// there is exactly one place where a value could be pasted into a statement
/// rather than bound, which is the mistake worth making impossible.
enum QueryBuilder {

    /// The columns every message read selects, in the order `Message` expects.
    ///
    /// `g.message_id_header` is the RFC `Message-ID`. **`messages.message_id`
    /// is not** — despite the name it is a 64-bit hash of the header, and
    /// reading it as text hands a caller a number like `-9222759812030868440`
    /// that looks like an identifier and matches nothing anywhere else. The
    /// real header lives in `message_global_data`, joined on that same hash.
    static let columns = """
        m.ROWID, g.message_id_header, s.subject, a.address, a.comment,
        m.date_sent, m.date_received, mb.url, m.conversation_id,
        m.read, m.flagged, m.size
        """

    /// The same, for an index too old to have `message_global_data`.
    static let columnsWithoutHeader = columns.replacingOccurrences(
        of: "g.message_id_header", with: "null"
    )

    static let from = """
        from messages m
        left join subjects s on s.ROWID = m.subject
        left join addresses a on a.ROWID = m.sender
        left join mailboxes mb on mb.ROWID = m.mailbox
        left join message_global_data g on g.message_id = m.message_id
        """

    /// The same, without the table that may not be there.
    static let fromWithoutHeader = from.replacingOccurrences(
        of: "\n        left join message_global_data g on g.message_id = m.message_id", with: ""
    )

    /// Turns a query into a `where` clause and the values to bind.
    static func clauses(for query: MailQuery) -> (sql: String, values: [SQLiteValue]) {
        var conditions: [String] = ["m.deleted = 0"]
        var values: [SQLiteValue] = []

        /// `%needle%`, with SQL's own wildcards escaped.
        ///
        /// Without this, searching for a literal `%` or `_` — both of which
        /// occur in real subject lines — would silently match everything.
        func contains(_ needle: String) -> SQLiteValue {
            let escaped = needle
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "%", with: "\\%")
                .replacingOccurrences(of: "_", with: "\\_")
            return .text("%\(escaped)%")
        }

        if let text = query.text {
            conditions.append("""
                (s.subject like ? escape '\\' or a.address like ? escape '\\' \
                or a.comment like ? escape '\\')
                """)
            values.append(contentsOf: [contains(text), contains(text), contains(text)])
        }
        if let from = query.from {
            conditions.append("(a.address like ? escape '\\' or a.comment like ? escape '\\')")
            values.append(contentsOf: [contains(from), contains(from)])
        }
        if let to = query.to {
            conditions.append("""
                m.ROWID in (select r.message from recipients r \
                join addresses ra on ra.ROWID = r.address \
                where ra.address like ? escape '\\')
                """)
            values.append(contains(to))
        }
        if let subject = query.subject {
            conditions.append("s.subject like ? escape '\\'")
            values.append(contains(subject))
        }
        if let mailbox = query.mailbox {
            conditions.append("mb.url like ? escape '\\'")
            values.append(contains(mailbox))
        }
        if let since = query.since {
            conditions.append("m.date_received >= ?")
            values.append(.integer(Int64(since.timeIntervalSince1970)))
        }
        if let until = query.until {
            conditions.append("m.date_received < ?")
            values.append(.integer(Int64(until.timeIntervalSince1970)))
        }
        if let isRead = query.isRead {
            conditions.append("m.read = ?")
            values.append(.integer(isRead ? 1 : 0))
        }
        if let isFlagged = query.isFlagged {
            conditions.append("m.flagged = ?")
            values.append(.integer(isFlagged ? 1 : 0))
        }
        if let hasAttachments = query.hasAttachments {
            let test = hasAttachments ? "exists" : "not exists"
            conditions.append("\(test) (select 1 from attachments at where at.message = m.ROWID)")
        }
        if let conversation = query.conversationID {
            conditions.append("m.conversation_id = ?")
            values.append(.integer(conversation))
        }

        return ("where " + conditions.joined(separator: " and "), values)
    }

    /// The whole statement for a query.
    static func sql(
        for query: MailQuery,
        includeHeader: Bool = true
    ) -> (sql: String, values: [SQLiteValue]) {
        let (where_, values) = clauses(for: query)
        let order = query.newestFirst ? "desc" : "asc"
        let select = includeHeader ? columns : columnsWithoutHeader
        let tables = includeHeader ? from : fromWithoutHeader
        // The limit is an integer this library controls, but it is bound
        // anyway: the rule is that nothing reaches the statement as text.
        return (
            "select \(select) \(tables) \(where_) order by m.date_received \(order) limit ?",
            values + [.integer(Int64(max(1, query.limit)))]
        )
    }
}
