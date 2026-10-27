//
//  MailStore.swift
//  AppleMail
//
//  Created by David Sherlock on 2026.
//
//  Mail's own index, read and never written.
//

import Foundation
import SQLiteReader

/// Everything Mail knows about your messages, read-only.
///
/// This opens Mail's `Envelope Index` — a plain SQLite database — with a
/// read-only connection and no copy, through swift-sqlite-reader. There is no code path here that writes to
/// it, and there should never be one: the schema is Apple's, undocumented, and
/// changed between versions. Changing a message goes through Mail itself; see
/// ``MailScript``.
///
/// ```swift
/// let store = try MailStore()
/// let recent = try store.search(MailQuery(from: "ada@example.com", limit: 20))
/// ```
public final class MailStore {

    private let database: SQLiteReader

    /// Where the index lives.
    public let path: String

    /// Whether this index carries the table holding the RFC `Message-ID`.
    ///
    /// Checked once rather than assumed: the schema is Apple's and
    /// undocumented, it has changed shape across store versions, and a missing
    /// table should cost one nil field rather than every query.
    private let hasGlobalData: Bool

    /// Opens Mail's index, or says why it cannot.
    ///
    /// - Parameter path: The index to read. Defaults to the newest version
    ///   Mail has on this Mac.
    public init(path: String? = nil) throws {
        let resolved = try path ?? Self.defaultPath()
        self.path = resolved
        // `.readOnly` on the live file, with no copy. Measured against Mail's
        // own index: a read-only connection sees the write-ahead log, so the
        // newest messages are there — copying the file first (the usual
        // advice) would miss anything still in the `-wal`, which on a busy
        // mailbox is everything that arrived today.
        do {
            self.database = try SQLiteReader(path: URL(fileURLWithPath: resolved), opening: .readOnly)
        } catch {
            throw MailError(error)
        }
        self.hasGlobalData = database.tables().contains("message_global_data")
            && database.columns(of: "message_global_data").contains("MESSAGE_ID_HEADER")
    }

    /// Runs a query, handing each row to `row`; values belong in
    /// `parameters`, bound in order, never pasted into the SQL.
    private func run(_ sql: String, _ parameters: [SQLiteValue] = [], row: (SQLiteRow) -> Void) throws {
        do { try database.query(sql, parameters, row: row) } catch { throw MailError(error) }
    }

    // MARK: - Finding the index

    /// Mail's data directory, newest format first.
    ///
    /// The `V10` in the path is the **store format**, not the macOS version,
    /// and it has stepped roughly once per release: V2 in Mountain Lion up to
    /// V10 now. So this looks for whatever versions are present and takes the
    /// highest rather than naming one — a hardcoded `V10` would break on the
    /// next release, silently, by reading an old index full of stale mail.
    public static func defaultPath() throws -> String {
        let root = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mail", isDirectory: true)

        let versions = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
        let candidates = versions
            .compactMap { name -> (Int, String)? in
                guard name.hasPrefix("V"), let number = Int(name.dropFirst()) else { return nil }
                return (number, name)
            }
            .sorted { $0.0 > $1.0 }

        for (_, version) in candidates {
            let index = root
                .appendingPathComponent(version, isDirectory: true)
                .appendingPathComponent("MailData/Envelope Index")
            if FileManager.default.fileExists(atPath: index.path) { return index.path }
        }
        throw MailError.noMailData(root.path)
    }

    // MARK: - Reading

    /// The messages matching a query, newest first by default.
    public func search(_ query: MailQuery = MailQuery()) throws -> [Message] {
        var (sql, values) = QueryBuilder.sql(for: query, includeHeader: hasGlobalData)

        // Applied after the SQL is built rather than inside the builder: it
        // needs the mailbox list, which is a second query, and the builder is
        // kept free of I/O so it can be tested on its own.
        if query.incomingOnly, query.mailbox == nil {
            let outgoing = try mailboxes().filter { !$0.isIncoming }.map(\.id)
            if !outgoing.isEmpty {
                let holes = outgoing.map { _ in "?" }.joined(separator: ",")
                sql = sql.replacingOccurrences(
                    of: " order by",
                    with: " and m.mailbox not in (\(holes)) order by"
                )
                values.insert(contentsOf: outgoing.map { SQLiteValue.integer($0) },
                              at: values.count - 1)
            }
        }

        var messages: [Message] = []
        try run(sql, values) { row in
            messages.append(Self.message(from: row))
        }
        return try attaching(to: messages)
    }

    /// One message by its row identifier.
    public func message(id: Int64) throws -> Message {
        var found: Message?
        let select = hasGlobalData ? QueryBuilder.columns : QueryBuilder.columnsWithoutHeader
        let tables = hasGlobalData ? QueryBuilder.from : QueryBuilder.fromWithoutHeader
        try run(
            "select \(select) \(tables) where m.ROWID = ? limit 1",
            [.integer(id)]
        ) { row in
            found = Self.message(from: row)
        }
        guard let found else { throw MailError.noSuchMessage(id) }
        return try attaching(to: [found])[0]
    }

    /// Every message in a thread, oldest first — which is how a thread reads.
    public func conversation(id: Int64, limit: Int = 200) throws -> [Message] {
        try search(MailQuery(
            incomingOnly: false, conversationID: id, limit: limit, newestFirst: false
        ))
    }

    /// Every mailbox, across every account.
    public func mailboxes() throws -> [Mailbox] {
        var boxes: [Mailbox] = []
        try run(
            "select ROWID, url, total_count, unread_count from mailboxes order by url"
        ) { row in
            guard let url = row[1].decodedString else { return }
            boxes.append(Mailbox(
                id: row.integer(0),
                url: url,
                totalCount: Int(row.integer(2)),
                unreadCount: Int(row.integer(3))
            ))
        }
        return boxes
    }

    /// Who sends you the most mail, most first.
    ///
    /// - Parameters:
    ///   - limit: How many senders to return.
    ///   - since: Only count mail received on or after this.
    public func senders(limit: Int = 25, since: Date? = nil) throws -> [SenderCount] {
        var sql = """
            select a.address, a.comment, count(*) as total,
                   max(m.date_received) as latest
            from messages m
            join addresses a on a.ROWID = m.sender
            where m.deleted = 0
            """
        var values: [SQLiteValue] = []
        if let since {
            sql += " and m.date_received >= ?"
            values.append(.integer(Int64(since.timeIntervalSince1970)))
        }
        sql += " group by a.ROWID order by total desc limit ?"
        values.append(.integer(Int64(max(1, limit))))

        var counts: [SenderCount] = []
        try run(sql, values) { row in
            guard let address = row[0].decodedString else { return }
            counts.append(SenderCount(
                sender: Address(address: address, name: row[1].decodedString),
                messages: Int(row.integer(2)),
                latest: Date(timeIntervalSince1970: TimeInterval(row.integer(3)))
            ))
        }
        return counts
    }

    /// Attachment names for a message, from the index.
    ///
    /// Names only — the index does not hold the bytes. ``MessageBody`` reads
    /// those out of the message file when it is on this Mac.
    public func attachmentNames(messageID: Int64) throws -> [String] {
        var names: [String] = []
        try run(
            "select name from attachments where message = ? order by ROWID",
            [.integer(messageID)]
        ) { row in
            if let name = row[0].nonEmptyString { names.append(name) }
        }
        return names
    }

    /// How many messages the index holds, and over what span.
    public func summary() throws -> StoreSummary {
        var total = 0
        var unread = 0
        var oldest: Date?
        var newest: Date?
        try run("""
            select count(*), sum(case when read = 0 then 1 else 0 end),
                   min(date_received), max(date_received)
            from messages where deleted = 0
            """) { row in
            total = Int(row.integer(0))
            unread = Int(row.integer(1))
            if !row[2].isNull { oldest = Date(timeIntervalSince1970: TimeInterval(row.integer(2))) }
            if !row[3].isNull { newest = Date(timeIntervalSince1970: TimeInterval(row.integer(3))) }
        }
        var mailboxCount = 0
        try run("select count(*) from mailboxes") { mailboxCount = Int($0.integer(0)) }
        return StoreSummary(
            messages: total, unread: unread, mailboxes: mailboxCount,
            oldest: oldest, newest: newest
        )
    }

    // MARK: - Internals

    /// Builds a message from a row of the standard column list.
    private static func message(from row: SQLiteRow) -> Message {
        Message(
            id: row.integer(0),
            messageID: row[1].decodedString,
            subject: row[2].decodedString ?? "",
            sender: Address(address: row[3].decodedString ?? "", name: row[4].decodedString),
            sentAt: Date(timeIntervalSince1970: TimeInterval(row.integer(5))),
            receivedAt: Date(timeIntervalSince1970: TimeInterval(row.integer(6))),
            mailbox: row[7].decodedString.map { Mailbox.split($0).name } ?? "",
            conversationID: row.integer(8),
            isRead: row.integer(9) != 0,
            isFlagged: row.integer(10) != 0,
            size: Int(row.integer(11))
        )
    }

    /// Fills in recipients and attachment names for a page of results.
    ///
    /// One query each for the whole page rather than two per message: a page
    /// of 50 was 101 round trips before, and the index is on somebody's disk.
    private func attaching(to messages: [Message]) throws -> [Message] {
        guard !messages.isEmpty else { return [] }
        let ids = messages.map(\.id)
        let holes = ids.map { _ in "?" }.joined(separator: ",")
        let values = ids.map { SQLiteValue.integer($0) }

        var recipients: [Int64: [Recipient]] = [:]
        try run("""
            select r.message, a.address, a.comment, r.type
            from recipients r join addresses a on a.ROWID = r.address
            where r.message in (\(holes)) order by r.position
            """, values) { row in
            guard let address = row[1].decodedString else { return }
            let kind = RecipientKind(rawValue: Int(row.integer(3))) ?? .to
            recipients[row.integer(0), default: []].append(Recipient(
                address: Address(address: address, name: row[2].decodedString), kind: kind
            ))
        }

        var attachments: [Int64: [String]] = [:]
        try run(
            "select message, name from attachments where message in (\(holes)) order by ROWID",
            values
        ) { row in
            guard let name = row[1].nonEmptyString else { return }
            attachments[row.integer(0), default: []].append(name)
        }

        return messages.map { message in
            Message(
                id: message.id,
                messageID: message.messageID,
                subject: message.subject,
                sender: message.sender,
                recipients: recipients[message.id] ?? [],
                sentAt: message.sentAt,
                receivedAt: message.receivedAt,
                mailbox: message.mailbox,
                conversationID: message.conversationID,
                isRead: message.isRead,
                isFlagged: message.isFlagged,
                size: message.size,
                attachmentNames: attachments[message.id] ?? []
            )
        }
    }
}

/// One sender, and how much they write.
public struct SenderCount: Sendable, Equatable, Codable {
    public let sender: Address
    public let messages: Int
    public let latest: Date
}

/// What the index holds.
public struct StoreSummary: Sendable, Equatable, Codable {
    public let messages: Int
    public let unread: Int
    public let mailboxes: Int
    public let oldest: Date?
    public let newest: Date?
}

private extension SQLiteRow {

    /// An integer column read as this store always has: 0 for NULL, a real truncated.
    func integer(_ index: Int) -> Int64 { self[index].truncatedInt.map(Int64.init) ?? 0 }
}
