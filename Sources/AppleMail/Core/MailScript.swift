//
//  MailScript.swift
//  AppleMail
//
//  Created by David Sherlock on 2026.
//
//  The only way this library changes anything: by asking Mail to.
//

import Foundation

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
/// Requires Automation permission for Mail, which macOS asks for once. Until
/// it is granted every call here fails with ``MailError/scriptFailed(_:)`` and
/// the read side is unaffected.
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
    @discardableResult
    public static func draft(
        to: [String],
        cc: [String] = [],
        subject: String,
        body: String,
        quoting: String? = nil
    ) throws -> String {
        for address in to + cc {
            guard address.contains("@"), !address.contains("\"") else {
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

        var script = """
            tell application "Mail"
                set theDraft to make new outgoing message with properties \
            {subject:\(literal(subject)), content:\(literal(content)), visible:true}
                tell theDraft

            """
        for address in to {
            script += "        make new to recipient at end of to recipients "
                + "with properties {address:\(literal(address))}\n"
        }
        for address in cc {
            script += "        make new cc recipient at end of cc recipients "
                + "with properties {address:\(literal(address))}\n"
        }
        script += """
                end tell
                activate
                return "drafted"
            end tell
            """

        return try run(script)
    }

    // MARK: - Marking

    /// Flags or unflags a message, found by its `Message-ID` header.
    ///
    /// Reversible, which is the whole reason it is here and `delete` is not.
    public static func setFlagged(_ flagged: Bool, messageID: String) throws {
        try mark(messageID: messageID, property: "flagged status", value: flagged ? "true" : "false")
    }

    /// Marks a message read or unread.
    public static func setRead(_ read: Bool, messageID: String) throws {
        try mark(messageID: messageID, property: "read status", value: read ? "true" : "false")
    }

    /// Sets one boolean property on the message with this header.
    ///
    /// Mail has no global "find by Message-ID", so every mailbox is asked in
    /// turn. Addressing by the RFC header rather than by position is the point:
    /// `message 3 of mailbox 2` means something different the moment mail
    /// arrives, and this is somebody's real mailbox.
    private static func mark(messageID: String, property: String, value: String) throws {
        guard messageID.hasPrefix("<"), messageID.hasSuffix(">"), !messageID.contains("\"") else {
            throw MailError.scriptFailed("\(messageID) is not a Message-ID")
        }

        let script = """
            tell application "Mail"
                set found to false
                repeat with anAccount in accounts
                    repeat with aMailbox in mailboxes of anAccount
                        try
                            set matches to (messages of aMailbox whose message id is \(literal(messageID)))
                            if (count of matches) > 0 then
                                set \(property) of item 1 of matches to \(value)
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
            """

        let result = try run(script)
        guard result != "notfound" else {
            throw MailError.scriptFailed("Mail has no message with that Message-ID")
        }
    }

    // MARK: - Internals

    /// An AppleScript string literal.
    ///
    /// Backslashes first, then quotes — the other order double-escapes and
    /// turns a subject containing a quotation mark into a syntax error, or
    /// worse, into script.
    static func literal(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    /// Runs a script, capturing both streams.
    private static func run(_ script: String) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]

        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err

        do {
            try process.run()
        } catch {
            throw MailError.scriptFailed("could not run osascript: \(error.localizedDescription)")
        }

        // Read before waiting: a full pipe blocks the child for ever, and an
        // AppleScript error is easily bigger than the buffer.
        let output = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let failure = String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            // -1743 is the one worth naming: it means the user has not granted
            // Automation permission, and no amount of retrying will change it.
            if failure.contains("-1743") || failure.lowercased().contains("not authori") {
                throw MailError.scriptFailed(
                    "not allowed to control Mail — System Settings ▸ Privacy & Security ▸ "
                        + "Automation, then allow your terminal to control Mail"
                )
            }
            throw MailError.scriptFailed(failure.isEmpty ? "osascript failed" : failure)
        }
        return output
    }
}
