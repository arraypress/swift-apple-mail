//
//  MailScript.swift
//  AppleMail
//
//  Created by David Sherlock on 2026.
//
//  The only way this library changes anything: by asking Mail to.
//

import Foundation

/// Runs AppleScript: the script's source, and the values it reads from `argv`
/// (`on run argv`), returning what the script printed.
///
/// The library does not run osascript itself. A caller passes the runner —
/// in the fleet, CLIKit's `OSAScript.run`, which has a hard timeout, reads
/// both pipes together and says whether a failure may have acted — so the
/// way scripts are run is one shared piece of code, not a copy here. Errors
/// the runner throws pass through unchanged.
public typealias AppleScriptRunner = @Sendable (_ source: String, _ arguments: [String]) throws -> String

/// Asking Mail.app to do something.
///
/// **Nothing in this library writes to Mail's index.** The schema is Apple's,
/// undocumented, and read by a running application that caches it — a direct
/// write would be corruption waiting for a restart. So every change goes
/// through Mail itself, over AppleScript, and the surface is deliberately
/// narrow: this can compose a draft, and it can flag or mark a message. It
/// cannot send, delete or move, because those are the operations whose
/// mistakes cannot be taken back.
///
/// **Every value goes in as `argv`, never into the script's source.** A
/// subject with a quote, a backslash or `end tell` in it is text, and an
/// escaping slip would make it code. The scripts are constants.
///
/// Requires Automation permission for Mail, which macOS asks for once. Until
/// it is granted every call here fails with the runner's error and the read
/// side is unaffected.
public enum MailScript {

    /// Whether this Mac can be asked at all.
    public static var isAvailable: Bool {
        FileManager.default.isExecutableFile(atPath: "/usr/bin/osascript")
    }

    // MARK: - Composing

    /// Opens a draft in Mail, filled in and **not sent**.
    ///
    /// The draft is left visible in Mail for a person to read, change and
    /// send. There is no parameter here that would send it: the decision to
    /// put mail in front of somebody else belongs to the person, not to the
    /// program, and an accidental `send: true` is not a mistake that can be
    /// undone.
    ///
    /// - Parameters:
    ///   - to: Recipients.
    ///   - cc: Copied recipients.
    ///   - subject: The subject line.
    ///   - body: The message text.
    ///   - quoting: Text to include below the new message, quoted with `>`.
    ///   - runner: Runs the script.
    @discardableResult
    public static func draft(
        to: [String],
        cc: [String] = [],
        subject: String,
        body: String,
        quoting: String? = nil,
        using runner: AppleScriptRunner
    ) throws -> String {
        try runner(Scripts.draft, draftArguments(to: to, cc: cc, subject: subject, body: body, quoting: quoting))
    }

    /// The draft script's `argv`: subject, content, how many `to`, then the
    /// `to` addresses, then the `cc` addresses.
    static func draftArguments(
        to: [String], cc: [String], subject: String, body: String, quoting: String?
    ) throws -> [String] {
        for address in to + cc {
            guard address.contains("@"), !address.contains("\""), !address.contains("\n") else {
                throw MailError.scriptFailed("\(address) is not an email address")
            }
        }

        var content = body
        if let quoting, !quoting.isEmpty {
            let quoted = quoting
                .split(separator: "\n", omittingEmptySubsequences: false)
                .map { "> " + $0 }
                .joined(separator: "\n")
            content += "\n\n" + quoted
        }
        return [subject, content, String(to.count)] + to + cc
    }

    // MARK: - Marking

    /// Flags or unflags a message, found by its `Message-ID` header.
    ///
    /// Reversible, which is the whole reason it is here and `delete` is not.
    public static func setFlagged(_ flagged: Bool, messageID: String, using runner: AppleScriptRunner) throws {
        try mark(Scripts.flag, messageID: messageID, value: flagged, using: runner)
    }

    /// Marks a message read or unread.
    public static func setRead(_ read: Bool, messageID: String, using runner: AppleScriptRunner) throws {
        try mark(Scripts.read, messageID: messageID, value: read, using: runner)
    }

    /// Sets one boolean property on the message with this header.
    ///
    /// Mail has no global "find by Message-ID", so every mailbox is asked in
    /// turn. Addressing by the RFC header rather than by position is the point:
    /// `message 3 of mailbox 2` means something different the moment mail
    /// arrives, and this is somebody's real mailbox.
    private static func mark(_ script: String, messageID: String, value: Bool,
                             using runner: AppleScriptRunner) throws {
        guard messageID.hasPrefix("<"), messageID.hasSuffix(">"), !messageID.contains("\"") else {
            throw MailError.scriptFailed("\(messageID) is not a Message-ID")
        }
        let result = try runner(script, [messageID, value ? "true" : "false"])
        guard result.trimmingCharacters(in: .whitespacesAndNewlines) != "notfound" else {
            throw MailError.scriptFailed("Mail has no message with that Message-ID")
        }
    }

    // MARK: - Scripts

    /// The scripts, as constants. Values arrive in `argv`.
    enum Scripts {

        /// `argv`: subject, content, count of `to`, the `to` addresses, the
        /// `cc` addresses.
        static let draft = """
            on run argv
                set theSubject to item 1 of argv
                set theContent to item 2 of argv
                set toCount to (item 3 of argv) as integer
                tell application "Mail"
                    set theDraft to make new outgoing message with properties \
            {subject:theSubject, content:theContent, visible:true}
                    tell theDraft
                        repeat with i from 4 to (3 + toCount)
                            make new to recipient at end of to recipients with properties {address:(item i of argv)}
                        end repeat
                        repeat with i from (4 + toCount) to (count of argv)
                            make new cc recipient at end of cc recipients with properties {address:(item i of argv)}
                        end repeat
                    end tell
                    activate
                    return "drafted"
                end tell
            end run
            """

        /// `argv`: Message-ID, `true` or `false`.
        static let flag = markScript(property: "flagged status")

        /// `argv`: Message-ID, `true` or `false`.
        static let read = markScript(property: "read status")

        /// The property name is one of two constants above, never a value.
        private static func markScript(property: String) -> String {
            """
            on run argv
                set theID to item 1 of argv
                set newValue to ((item 2 of argv) is "true")
                tell application "Mail"
                    set found to false
                    repeat with anAccount in accounts
                        repeat with aMailbox in mailboxes of anAccount
                            try
                                set matches to (messages of aMailbox whose message id is theID)
                                if (count of matches) > 0 then
                                    set \(property) of item 1 of matches to newValue
                                    set found to true
                                    exit repeat
                                end if
                            end try
                        end repeat
                        if found then exit repeat
                    end repeat
                    if found then
                        return "changed"
                    else
                        return "notfound"
                    end if
                end tell
            end run
            """
        }
    }
}
