//
//  MailError.swift
//  AppleMail
//
//  Created by David Sherlock on 2026.
//

import Foundation

/// What can go wrong reading Mail.
public enum MailError: Error, Equatable, Sendable, LocalizedError {

    /// Mail has never run here, or its data lives somewhere this does not know.
    case noMailData(String)

    /// The index is there, but this process may not read it.
    ///
    /// Almost always Full Disk Access. Nothing else about the file is unusual
    /// — it is a plain SQLite database owned by the user — and macOS refuses
    /// the open with a bare "unable to open database file", which tells a
    /// reader nothing.
    case notPermitted(String)

    /// SQLite refused.
    case queryFailed(String)

    /// No message with that identifier.
    ///
    /// Separate from ``queryFailed(_:)`` so a caller can tell "you asked for
    /// something that is not there" from "the index would not answer" — the
    /// first is the caller's mistake and the second is worth retrying.
    case noSuchMessage(Int64)

    /// The message is in the index but its body is not on this Mac.
    ///
    /// An ordinary state, not a fault: an IMAP account keeps the envelope
    /// locally and leaves the body on the server until something asks for it.
    case bodyNotLocal(id: Int64)

    /// The `.emlx` on disk is not shaped like one.
    case malformedMessage(String)

    /// Mail.app refused a change, or is not running and would not start.
    case scriptFailed(String)

    public var errorDescription: String? {
        switch self {
        case .noMailData(let path):
            "No Mail data at \(path) — Mail may never have run on this Mac"
        case .notPermitted(let path):
            "Not allowed to read \(path) — grant Full Disk Access to your terminal "
                + "in System Settings ▸ Privacy & Security ▸ Full Disk Access"
        case .noSuchMessage(let id):
            "No message with id \(id)"
        case .queryFailed(let reason):
            "Could not read the mail index: \(reason)"
        case .bodyNotLocal(let id):
            "Message \(id) has no copy on this Mac — its body is still on the server"
        case .malformedMessage(let reason):
            "That message file could not be read: \(reason)"
        case .scriptFailed(let reason):
            "Mail refused the change: \(reason)"
        }
    }
}
