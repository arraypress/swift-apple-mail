//
//  MailScript+Organising.swift
//  AppleMail
//
//  Created by David Sherlock on 2026.
//
//  Filing, marking and mailboxes — each a thin call into a script constant,
//  with the checks that must hold before Mail is asked at all.
//

import Foundation

public extension MailScript {

    // MARK: - Messages

    /// Moves messages into a mailbox.
    ///
    /// Every message and the destination are found before anything moves; if
    /// any is missing, nothing does. A message keeps its `Message-ID` but gets
    /// a new index id after a move — record the locator, not the id.
    ///
    /// - Returns: One step per message, in order.
    /// - Throws: ``MailError/scriptFailed(_:)`` when the destination is
    ///   refused (see ``MailboxSafety``), or when Mail could not find every
    ///   message or the destination — in both cases nothing was changed.
    static func move(_ messages: [MessageLocator], to destination: MailboxReference,
                     using runner: AppleScriptRunner) throws -> [ScriptStep] {
        try file(MailScriptSources.move, messages, to: destination, using: runner)
    }

    /// Copies messages into a mailbox, leaving each original where it is.
    static func copy(_ messages: [MessageLocator], to destination: MailboxReference,
                     using runner: AppleScriptRunner) throws -> [ScriptStep] {
        try file(MailScriptSources.copy, messages, to: destination, using: runner)
    }

    /// Marks messages read or unread.
    static func setRead(_ read: Bool, _ messages: [MessageLocator],
                        using runner: AppleScriptRunner) throws -> [ScriptStep] {
        try batch(MailScriptSources.read, operation: [read ? "true" : "false"], messages, using: runner)
    }

    /// Flags messages — in a colour, when one is given — or removes the flag.
    ///
    /// - Parameter color: The colour, `nil` with `flagged: true` for Mail's
    ///   default, ignored when unflagging.
    static func setFlag(_ flagged: Bool, color: FlagColor? = nil, _ messages: [MessageLocator],
                        using runner: AppleScriptRunner) throws -> [ScriptStep] {
        if flagged, let color {
            return try batch(MailScriptSources.flagIndex, operation: [String(color.rawValue)], messages, using: runner)
        }
        return try batch(MailScriptSources.flagged, operation: [flagged ? "true" : "false"], messages, using: runner)
    }

    // MARK: - Mailboxes

    /// What creating a mailbox found.
    enum CreateOutcome: String, Sendable {
        case created
        /// It was already there; nothing was made.
        case alreadyExists
    }

    /// Makes a mailbox, and any folders above it.
    static func createMailbox(_ mailbox: MailboxReference, using runner: AppleScriptRunner) throws -> CreateOutcome {
        if let problem = MailboxSafety.pathProblem(mailbox.path) { throw MailError.scriptFailed(problem) }
        if MailboxSafety.isSystem(mailbox.path) {
            throw MailError.scriptFailed("\(mailbox.path) is one of Mail's own mailboxes")
        }
        switch try runner(MailScriptSources.createMailbox, [mailbox.accountID ?? "", mailbox.path]) {
        case "exists": return .alreadyExists
        case "created": return .created
        default:
            throw MailError.scriptFailed(
                "Mail accepted the request but \(mailbox.described) could not be found afterwards"
            )
        }
    }

    /// Renames a mailbox's last component, keeping it where it is.
    ///
    /// - Returns: The path it has now.
    @discardableResult
    static func renameMailbox(_ mailbox: MailboxReference, to name: String,
                              using runner: AppleScriptRunner) throws -> MailboxReference {
        if let problem = MailboxSafety.refusalToChange(mailbox.path) { throw MailError.scriptFailed(problem) }
        if let problem = MailboxSafety.newNameProblem(name) { throw MailError.scriptFailed(problem) }
        let after = MailboxReference(accountID: mailbox.accountID,
                                     path: ScriptReplies.renamedPath(mailbox, to: name))
        switch try runner(MailScriptSources.renameMailbox,
                          [mailbox.accountID ?? "", mailbox.path, name, after.path]) {
        case "renamed": return after
        case "nobox": throw MailError.scriptFailed("no mailbox \(mailbox.described) — nothing was changed")
        case "taken": throw MailError.scriptFailed("\(after.described) already exists — nothing was changed")
        default:
            throw MailError.scriptFailed(
                "Mail accepted the rename but \(after.described) could not be found afterwards"
            )
        }
    }

    // MARK: - Internals

    private static func file(_ script: String, _ messages: [MessageLocator], to destination: MailboxReference,
                             using runner: AppleScriptRunner) throws -> [ScriptStep] {
        if let refusal = MailboxSafety.refusalAsDestination(destination.path) {
            throw MailError.scriptFailed(refusal)
        }
        return try batch(script, operation: [destination.accountID ?? "", destination.path], messages,
                         target: destination, using: runner)
    }

    private static func batch(_ script: String, operation: [String], _ messages: [MessageLocator],
                              target: MailboxReference? = nil,
                              using runner: AppleScriptRunner) throws -> [ScriptStep] {
        guard !messages.isEmpty else { return [] }
        for locator in messages where !MessageIDs.isUsable(locator.messageID) {
            throw MailError.scriptFailed("\(locator.messageID) is not a Message-ID")
        }
        let reply = try runner(script, ScriptReplies.batchArguments(operation: operation, messages: messages))
        return try ScriptReplies.batchSteps(reply, count: messages.count, target: target)
    }
}
