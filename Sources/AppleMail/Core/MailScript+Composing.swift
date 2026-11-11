//
//  MailScript+Composing.swift
//  AppleMail
//
//  Created by David Sherlock on 2026.
//
//  Replies and forwards, opened in Mail and never sent; and asking Mail to
//  fetch.
//

import Foundation

public extension MailScript {

    /// Opens Mail's own reply to a message — threaded, addressed and quoted
    /// by Mail — and stops. **Not sent**, and there is no body: Mail does not
    /// let a script write into a reply (measured: the content reads back
    /// empty), so the person types it. ``draft(to:cc:subject:body:quoting:using:)``
    /// is the way to hand over text, at the cost of threading.
    static func reply(to message: MessageLocator, all: Bool = false, using runner: AppleScriptRunner) throws {
        try expectOpened(runner(MailScriptSources.reply, [
            message.mailbox.accountID ?? "", message.mailbox.path, message.messageID, all ? "true" : "false",
        ]))
    }

    /// Opens Mail's forward of a message, addressed to `recipients`. **Not
    /// sent.**
    static func forward(_ message: MessageLocator, to recipients: [String], using runner: AppleScriptRunner) throws {
        for address in recipients {
            guard address.contains("@"), !address.contains("\""), !address.contains(where: \.isNewline) else {
                throw MailError.scriptFailed("\(address) is not an email address")
            }
        }
        try expectOpened(runner(MailScriptSources.forward, [
            message.mailbox.accountID ?? "", message.mailbox.path, message.messageID,
        ] + recipients))
    }

    /// Asks every account to fetch new mail, and synchronises each IMAP
    /// account with its server. The index catches up on Mail's own schedule
    /// after that.
    ///
    /// - Returns: The names of the accounts synchronised.
    @discardableResult
    static func checkForNewMail(using runner: AppleScriptRunner) throws -> [String] {
        let lines = try runner(MailScriptSources.checkForNewMail, [])
            .split(whereSeparator: \.isNewline).map(String.init)
        guard lines.first == "checked" else {
            throw MailError.scriptFailed("Mail did not confirm it was asked to check for new mail")
        }
        return Array(lines.dropFirst())
    }

    private static func expectOpened(_ reply: String) throws {
        guard reply == "opened" else {
            throw MailError.scriptFailed("Mail has no message with that Message-ID in that mailbox")
        }
    }
}
