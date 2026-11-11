//
//  MailStore+Insights.swift
//  AppleMail
//
//  Created by David Sherlock on 2026.
//
//  Questions about your mail that the index can answer without Mail: what is
//  waiting on you, where a sender's mail usually goes, which mailbox is which,
//  and the message itself as a file.
//

import Foundation
import SQLiteReader

/// A sender whose mail sitting in one mailbox usually lives in another.
public struct FilingSuggestion: Sendable, Equatable, Codable {

    /// Who sent it.
    public let sender: Address

    /// Where the rest of their mail is.
    public let destination: MailboxReference

    /// How many of their messages elsewhere are in ``destination``.
    public let agreeing: Int

    /// How many of their messages are elsewhere at all.
    public let history: Int

    /// The messages that would move, still in the source mailbox.
    public let messages: [Message]

    public init(sender: Address, destination: MailboxReference, agreeing: Int, history: Int, messages: [Message]) {
        self.sender = sender
        self.destination = destination
        self.agreeing = agreeing
        self.history = history
        self.messages = messages
    }
}

public extension MailStore {

    // MARK: - Lookups

    /// The mailbox at exactly this path, in this account (or On My Mac when
    /// `accountID` is `nil`), if the index lists it.
    func mailbox(_ reference: MailboxReference) throws -> Mailbox? {
        try mailboxes().first { $0.reference == reference }
    }

    /// Mail's account identifiers, for the accounts that have mailboxes here.
    func accountIDs() throws -> [String] {
        Array(Set(try mailboxes().compactMap(\.accountID))).sorted()
    }

    /// Every message carrying this `Message-ID`, with or without angle
    /// brackets, newest first.
    ///
    /// The way back to a message after it moves: its row id changes, its
    /// header does not. **It is not unique** — a copy carries the same header
    /// as its original, and so does a duplicate delivery — so a caller acting
    /// on one must refuse when this returns more than one, rather than pick.
    func messages(messageID: String) throws -> [Message] {
        let bare = MessageIDs.bare(messageID)
        var ids: [Int64] = []
        try run("""
            select m.ROWID from messages m
            join message_global_data g on g.message_id = m.message_id
            where m.deleted = 0 and g.message_id_header in (?, ?)
            order by m.date_received desc, m.ROWID desc
            """, [.text("<\(bare)>"), .text(bare)]) { row in ids.append(row.integer(0)) }
        return try messages(ids: ids)
    }

    /// Messages by row id, in the order given; ids the index does not hold are
    /// skipped.
    func messages(ids: [Int64]) throws -> [Message] {
        var found: [Message] = []
        for id in ids {
            if let message = try? message(id: id) { found.append(message) }
        }
        return found
    }

    // MARK: - Awaiting reply

    /// Conversations where somebody else wrote last, and it was a person.
    ///
    /// "You" is every address that has sent from one of your Sent mailboxes.
    /// A conversation counts when its newest message — across your incoming
    /// mailboxes and Sent, but not Trash, Junk or Drafts — is from somebody
    /// else and Mail does not class it as machine-sent. One row per
    /// conversation: that newest message.
    ///
    /// - Parameters:
    ///   - since: Only conversations whose newest message arrived on or after this.
    ///   - limit: How many to return, newest first.
    func awaitingReply(since: Date, limit: Int = 50) throws -> [Message] {
        let boxes = try mailboxes()
        let sent = boxes.filter { Self.isSent($0) }.map(\.id)
        let counted = boxes.filter { $0.isIncoming || Self.isSent($0) }.map(\.id)
        guard !counted.isEmpty else { return [] }

        let countedHoles = counted.map { _ in "?" }.joined(separator: ",")
        let sentClause: String
        var values: [SQLiteValue] = counted.map { .integer($0) } + [.integer(Int64(since.timeIntervalSince1970))]
        if sent.isEmpty {
            sentClause = ""
        } else {
            let sentHoles = sent.map { _ in "?" }.joined(separator: ",")
            sentClause = "and m.sender not in (select distinct sender from messages where mailbox in (\(sentHoles)))"
            values += sent.map { .integer($0) }
        }
        values += [.integer(Int64(max(1, limit)))]

        var ids: [Int64] = []
        try run("""
            with latest as (
                select conversation_id as cid, max(date_received) as newest
                from messages
                where deleted = 0 and conversation_id != 0 and mailbox in (\(countedHoles))
                group by conversation_id
                having max(date_received) >= ?
            )
            select max(m.ROWID) from messages m
            join latest l on l.cid = m.conversation_id and l.newest = m.date_received
            where m.deleted = 0 and m.automated_conversation != 2 \(sentClause)
            group by m.conversation_id
            order by max(m.date_received) desc
            limit ?
            """, values) { row in ids.append(row.integer(0)) }
        return try messages(ids: ids)
    }

    // MARK: - Filing suggestions

    /// Senders whose mail in `source` would fit where the rest of their mail
    /// already is.
    ///
    /// For each sender with mail in `source`, their other mail is counted per
    /// mailbox (incoming mailboxes only, `source` excluded). When they have at
    /// least `minimumHistory` messages elsewhere and at least `agreement` of
    /// them are in one mailbox, that mailbox is suggested.
    ///
    /// These are suggestions, not decisions — the counts come with them so a
    /// person can judge. The thresholds are a starting point chosen by hand,
    /// not calibrated.
    func filingSuggestions(in source: MailboxReference, minimumHistory: Int = 3,
                           agreement: Double = 0.8, scan: Int = 500) throws -> [FilingSuggestion] {
        let boxes = try mailboxes()
        guard let sourceBox = boxes.first(where: { $0.reference == source }) else { return [] }
        let incoming = Dictionary(uniqueKeysWithValues: boxes
            .filter { $0.isIncoming && $0.id != sourceBox.id && !MailboxSafety.isSystem($0.name) }
            .map { ($0.id, $0) })

        var waiting: [Int64: [Int64]] = [:]          // sender row → message ids in source
        var senderAddress: [Int64: Address] = [:]
        try run("""
            select m.ROWID, m.sender, a.address, a.comment from messages m
            join addresses a on a.ROWID = m.sender
            where m.deleted = 0 and m.mailbox = ?
            order by m.date_received desc limit ?
            """, [.integer(sourceBox.id), .integer(Int64(max(1, scan)))]) { row in
            let sender = row.integer(1)
            waiting[sender, default: []].append(row.integer(0))
            if let address = row[2].decodedString {
                senderAddress[sender] = Address(address: address, name: row[3].decodedString)
            }
        }

        var suggestions: [FilingSuggestion] = []
        for (sender, ids) in waiting {
            guard let address = senderAddress[sender] else { continue }
            var perBox: [Int64: Int] = [:]
            try run("""
                select mailbox, count(*) from messages
                where deleted = 0 and sender = ? and mailbox != ?
                group by mailbox
                """, [.integer(sender), .integer(sourceBox.id)]) { row in
                let box = row.integer(0)
                if incoming[box] != nil { perBox[box] = Int(row.integer(1)) }
            }
            let history = perBox.values.reduce(0, +)
            guard history >= minimumHistory,
                  let (best, agreeing) = perBox.max(by: { $0.value < $1.value }),
                  Double(agreeing) / Double(history) >= agreement,
                  let destination = incoming[best]
            else { continue }
            suggestions.append(FilingSuggestion(
                sender: address, destination: destination.reference,
                agreeing: agreeing, history: history, messages: try messages(ids: ids)
            ))
        }
        return suggestions.sorted { ($0.messages.count, $0.agreeing) > ($1.messages.count, $1.agreeing) }
    }

    // MARK: - Export

    /// The message as a standard `.eml` — the RFC 822 bytes from Mail's
    /// `.emlx`, without Mail's length line and trailing plist.
    ///
    /// - Throws: ``MailError/bodyNotLocal(id:)`` when Mail has not downloaded it.
    func rawMessage(id: Int64) throws -> Data {
        _ = try message(id: id)
        guard let url = Emlx.url(forMessage: id) else { throw MailError.bodyNotLocal(id: id) }
        guard let data = FileManager.default.contents(atPath: url.path) else {
            throw MailError.bodyNotLocal(id: id)
        }
        return try Emlx.split(data)
    }

    // MARK: - Internals

    /// Whether this is a mailbox mail leaves from.
    private static func isSent(_ box: Mailbox) -> Bool {
        let leaf = box.name.split(separator: "/").last.map(String.init)?.lowercased() ?? ""
        return ["sent messages", "sent", "sent items", "sent mail"].contains(leaf)
    }
}
