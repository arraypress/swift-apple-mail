//
//  MailboxSafety.swift
//  AppleMail
//
//  Created by David Sherlock on 2026.
//
//  The mailboxes nothing here may rename, remove, or put mail into — decided
//  in one place, as pure functions, so the rules can be tested without Mail.
//

import Foundation

/// Which mailboxes are off limits, and for what.
public enum MailboxSafety {

    /// Mail's own mailboxes. Never renamed or removed: Mail, the server and
    /// every other device depend on them by name.
    ///
    /// Matched against the WHOLE path, case-insensitively — these live at the
    /// top level, and a folder of your own called `Projects/Archive` is yours.
    /// `Outbox` and `SendLater` are On My Mac mailboxes Mail creates itself
    /// (seen in the index as `local://…/Outbox`, `local://…/SendLater`).
    static let system: Set<String> = [
        "inbox", "sent messages", "sent", "sent items", "drafts", "trash", "deleted messages",
        "deleted items", "junk", "junk e-mail", "spam", "bulk mail", "archive", "outbox",
        "sendlater", "notes", "all mail", "important", "starred",
    ]

    /// Places mail must never be moved or copied into, because something
    /// later deletes or sends what is there: Trash and Deleted Messages are
    /// emptied on a schedule, Junk and Spam too, and Drafts, Outbox and
    /// SendLater are queues of mail on its way out.
    ///
    /// `INBOX` and `Archive` are NOT here: moving mail back to the inbox, or
    /// into the archive, is ordinary filing.
    static let refusedDestinations: Set<String> = [
        "sent messages", "sent", "sent items", "drafts", "trash", "deleted messages",
        "deleted items", "junk", "junk e-mail", "spam", "bulk mail", "outbox", "sendlater",
        "notes",
    ]

    /// Whether `path` is one of Mail's own mailboxes.
    public static func isSystem(_ path: String) -> Bool {
        let lowered = normalised(path)
        return system.contains(lowered) || lowered.hasPrefix("[gmail]") || lowered.hasPrefix("[google mail]")
    }

    /// Why mail may not go into `path`, or `nil` when it may.
    public static func refusalAsDestination(_ path: String) -> String? {
        let lowered = normalised(path)
        if refusedDestinations.contains(lowered) || lowered.hasPrefix("[gmail]") || lowered.hasPrefix("[google mail]") {
            return "\(path) is a mailbox Mail empties or sends from; nothing here puts mail there"
        }
        return nil
    }

    /// Why `path` cannot be renamed or removed, or `nil` when it can.
    public static func refusalToChange(_ path: String) -> String? {
        isSystem(path) ? "\(path) is one of Mail's own mailboxes; nothing here renames or removes it" : nil
    }

    /// Why `path` is not a usable mailbox path, or `nil` when it is.
    ///
    /// `Accounting/Tax` is fine; an empty name, a leading or trailing `/`, an
    /// empty component (`a//b`), or a control character is not.
    public static func pathProblem(_ path: String) -> String? {
        if path.trimmingCharacters(in: .whitespaces).isEmpty { return "a mailbox needs a name" }
        if path.hasPrefix("/") || path.hasSuffix("/") { return "\(path): no leading or trailing /" }
        if path.contains("//") { return "\(path): an empty folder name between slashes" }
        if path.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) {
            return "a mailbox name cannot contain control characters"
        }
        if path.split(separator: "/").contains(where: { $0.trimmingCharacters(in: .whitespaces).isEmpty }) {
            return "\(path): a folder name cannot be blank"
        }
        if path.count > 200 { return "a mailbox path longer than 200 characters" }
        return nil
    }

    /// Why `name` cannot be the new name of a mailbox, or `nil` when it can.
    ///
    /// A rename changes only the last component — Mail keeps the folder where
    /// it is (measured: renaming `Inbox Test/Sub` to `Renamed` gave
    /// `Inbox Test/Renamed`) — so a `/` here would mean something it cannot do.
    public static func newNameProblem(_ name: String) -> String? {
        if name.contains("/") { return "a new name is one folder name, without /; rename keeps the folder where it is" }
        if let problem = pathProblem(name) { return problem }
        if isSystem(name) { return "\(name) is the name of one of Mail's own mailboxes" }
        return nil
    }

    private static func normalised(_ path: String) -> String {
        path.trimmingCharacters(in: .whitespaces).lowercased()
    }
}
