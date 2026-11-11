//
//  RuleActions.swift
//  AppleMail
//
//  Created by David Sherlock on 2026.
//

import Foundation

/// What a rule made by this library does to matching mail.
///
/// Only actions that can be put back: filing it, copying it, marking it read,
/// flagging it. There is no field for deleting, forwarding, redirecting,
/// replying or running a script — a rule acts on mail nobody has seen yet,
/// with nobody watching. See ``RuleSafety``.
public struct RuleActions: Sendable, Equatable, Codable {

    /// Move matching mail here.
    public var moveTo: MailboxReference?

    /// Copy matching mail here, leaving it where it arrived.
    public var copyTo: MailboxReference?

    /// Mark matching mail read.
    public var markRead: Bool

    /// Flag matching mail in this colour.
    public var flag: FlagColor?

    public init(moveTo: MailboxReference? = nil, copyTo: MailboxReference? = nil,
                markRead: Bool = false, flag: FlagColor? = nil) {
        self.moveTo = moveTo
        self.copyTo = copyTo
        self.markRead = markRead
        self.flag = flag
    }
}
