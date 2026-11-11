//
//  MailScriptSources.swift
//  AppleMail
//
//  Created by David Sherlock on 2026.
//
//  Every AppleScript this library runs, as constants. Values arrive in `argv`
//  and are never spliced into source; the only things ever interpolated below
//  are other constants from this file (an action statement, a rule type).
//
//  Each behaviour these rely on was measured against Mail on macOS 27 before
//  it was written down here — see the notes beside each.
//

import Foundation

enum MailScriptSources {

    // MARK: - Shared

    /// Finds a mailbox from an account id (`""` for On My Mac) and a path.
    ///
    /// Returns a reference without checking it — `get name of` the result to
    /// find vOut whether it exists (a missing one raises -1728). Measured:
    /// `mailbox "Work/Invoices" of account id "…"` resolves a nested
    /// path directly; `mailbox "Inbox Test"` with no account is On My Mac.
    static let boxHandler = """
        on boxFor(vAccountID, vThePath)
            tell application "Mail"
                if vAccountID is "" then return mailbox vThePath
                return mailbox vThePath of (first account whose id is vAccountID)
            end tell
        end boxFor

        on boxExists(vAccountID, vThePath)
            try
                tell application "Mail" to get name of (my boxFor(vAccountID, vThePath))
                return true
            on error
                return false
            end try
        end boxExists

        on pathOf(vTheBox)
            tell application "Mail"
                set vThePath to name of vTheBox
                set vCurrent to vTheBox
                repeat 32 times
                    try
                        set vCurrent to container of vCurrent
                        set vThePath to (name of vCurrent) & "/" & vThePath
                    on error
                        exit repeat
                    end try
                end repeat
                return vThePath
            end tell
        end pathOf
        """

    // MARK: - Batches over messages

    /// A script that finds every message first and only then vActs on each.
    ///
    /// `argv`: how many operation arguments follow, the operation arguments,
    /// how many messages, then for each message its account id, mailbox path
    /// and bare `Message-ID`.
    ///
    /// Replies, one per line: `notarget` (the destination does not exist —
    /// nothing done), or `missing` followed by `index:count` for each message
    /// that did not resolve to exactly one (nothing done), or one `ok` per
    /// message done, ending in `fail:number:text` if Mail refused one (the
    /// rest were not attempted).
    ///
    /// - Parameters:
    ///   - prepare: Statements run before the search — resolving a target.
    ///   - action: The statement applied to each message, which is `m`.
    static func batch(prepare: String = "", action: String) -> String {
        """
        \(boxHandler)

        on run argv
            set vOpCount to (item 1 of argv) as integer
            set vBase to 2 + vOpCount
            set vCount to (item vBase of argv) as integer
            set vFound to {}
            set vProblems to ""
            tell application "Mail"
                \(prepare)
                repeat with i from 1 to vCount
                    set vSlot to vBase + (i - 1) * 3
                    set vHits to -1
                    try
                        set vSrc to my boxFor(item (vSlot + 1) of argv, item (vSlot + 2) of argv)
                        set vMatches to (messages of vSrc whose message id is (item (vSlot + 3) of argv))
                        set vHits to count of vMatches
                    end try
                    if vHits is 1 then
                        set end of vFound to item 1 of vMatches
                    else
                        set vProblems to vProblems & i & ":" & vHits & linefeed
                    end if
                end repeat
                if vProblems is not "" then return "missing" & linefeed & vProblems
                set vOut to ""
                repeat with i from 1 to count of vFound
                    set m to item i of vFound
                    try
                        \(action)
                        set vOut to vOut & "ok" & linefeed
                    on error vErrText number vErrNum
                        return vOut & "fail:" & vErrNum & ":" & vErrText
                    end try
                end repeat
                return vOut
            end tell
        end run
        """
    }

    /// Resolves the destination from operation arguments 1 and 2 (account id,
    /// path) and stops with `notarget` before any message is looked at.
    static let resolveTarget = """
        set vTargetBox to missing value
        try
            set vTargetBox to my boxFor(item 2 of argv, item 3 of argv)
            get name of vTargetBox
        on error
            return "notarget"
        end try
        """

    /// Measured on a local copy: `move m to box` moves it, and the message
    /// keeps its `message id`.
    static let move = batch(prepare: resolveTarget, action: "move m to vTargetBox")

    /// Measured: `duplicate` leaves the original where it was (count 1 in the
    /// source before and after) and puts one copy in the destination.
    static let copy = batch(prepare: resolveTarget, action: "duplicate m to vTargetBox")

    /// Operation argument 1: `true` or `false`.
    static let read = batch(action: "set read status of m to ((item 2 of argv) is \"true\")")

    /// Operation argument 1: `true` or `false`.
    static let flagged = batch(action: "set flagged status of m to ((item 2 of argv) is \"true\")")

    /// Operation argument 1: a flag index, 0–6 for a colour or -1 for none.
    /// Measured: 3 flags it green (flagged becomes true); -1 removes the flag.
    static let flagIndex = batch(action: "set flag index of m to ((item 2 of argv) as integer)")

    // MARK: - Mailboxes

    /// `argv`: account id (`""` for On My Mac), path.
    /// Replies `exists`, `created`, or `unconfirmed`.
    ///
    /// Each missing level is made on its own, top first: `A`, then `A/B`.
    ///
    /// Measured on iCloud (2026-11-12): asking for `A/B` in one go when `A`
    /// did not exist made `A` as a container only — IMAP's `\Noselect`,
    /// greyed out on an iPhone. Mail on the Mac showed it as an ordinary
    /// mailbox and accepted a move into it, and minutes later the server put
    /// the message back where it came from. Made on their own, every level
    /// holds mail. With no `at`, a mailbox is made under On My Mac.
    static let createMailbox = """
        \(boxHandler)

        on run argv
            set vAccountID to item 1 of argv
            set vThePath to item 2 of argv
            if my boxExists(vAccountID, vThePath) then return "exists"
            set vSaved to AppleScript's text item delimiters
            set AppleScript's text item delimiters to "/"
            set vParts to text items of vThePath
            set AppleScript's text item delimiters to vSaved
            set vSoFar to ""
            repeat with vPart in vParts
                if vSoFar is "" then
                    set vSoFar to (vPart as text)
                else
                    set vSoFar to vSoFar & "/" & (vPart as text)
                end if
                if not my boxExists(vAccountID, vSoFar) then
                    tell application "Mail"
                        if vAccountID is "" then
                            make new mailbox with properties {name:vSoFar}
                        else
                            make new mailbox at (first account whose id is vAccountID) with properties {name:vSoFar}
                        end if
                    end tell
                    if not my boxExists(vAccountID, vSoFar) then return "unconfirmed"
                end if
            end repeat
            return "created"
        end run
        """

    /// `argv`: account id, path, new name, the path it will have afterwards.
    /// Replies `nobox`, `taken`, `renamed` or `unconfirmed`.
    ///
    /// Measured: setting the name of `Inbox Test/Sub` to `Renamed` gives
    /// `Inbox Test/Renamed` — the folder stays where it is.
    static let renameMailbox = """
        \(boxHandler)

        on run argv
            set vAccountID to item 1 of argv
            if not my boxExists(vAccountID, item 2 of argv) then return "nobox"
            if my boxExists(vAccountID, item 4 of argv) then return "taken"
            tell application "Mail"
                set vTheBox to my boxFor(vAccountID, item 2 of argv)
                set name of vTheBox to (item 3 of argv)
            end tell
            if my boxExists(vAccountID, item 4 of argv) then return "renamed"
            return "unconfirmed"
        end run
        """

    // MARK: - Rules

    /// Field separator (U+001F) and record separator (U+001E) for listings:
    /// characters no rule name or condition will contain.
    static let fieldSeparator: Character = "\u{1F}"
    static let recordSeparator: Character = "\u{1E}"
    static let itemSeparator: Character = "\u{1D}"

    /// No `argv`. One record per rule: name, enabled, all-conditions, the
    /// conditions, the actions — every action Mail reports, so a rule that
    /// deletes or forwards says so.
    static let listRules = """
        \(boxHandler)

        on run argv
            set vFs to character id 31
            set vRs to character id 30
            set vSep3 to character id 29
            set vOut to ""
            tell application "Mail"
                repeat with r in rules
                    set vConds to ""
                    repeat with c in rule conditions of r
                        set vConds to vConds & (rule type of c as text) & " " & (qualifier of c as text) & " " & (expression of c) & vSep3
                    end repeat
                    set vActs to ""
                    try
                        if should move message of r then set vActs to vActs & "move to " & my pathOf(move message of r) & vSep3
                    end try
                    try
                        if should copy message of r then set vActs to vActs & "copy to " & my pathOf(copy message of r) & vSep3
                    end try
                    if delete message of r then set vActs to vActs & "delete" & vSep3
                    if (forward message of r) is not "" then set vActs to vActs & "forward to " & (forward message of r) & vSep3
                    if (redirect message of r) is not "" then set vActs to vActs & "redirect to " & (redirect message of r) & vSep3
                    if (reply text of r) is not "" then set vActs to vActs & "reply" & vSep3
                    if mark read of r then set vActs to vActs & "mark read" & vSep3
                    if mark flagged of r then set vActs to vActs & "flag" & vSep3
                    try
                        if (run script of r) is not missing value then set vActs to vActs & "run script" & vSep3
                    end try
                    if stop evaluating rules of r then set vActs to vActs & "stop evaluating rules" & vSep3
                    set vOut to vOut & (name of r) & vFs & (enabled of r) & vFs & (all conditions must be met of r) & vFs & vConds & vFs & vActs & vRs
                end repeat
            end tell
            return vOut
        end run
        """

    /// A rule that matches one header and does only what ``RuleActions``
    /// allows: move, copy, mark read, flag.
    ///
    /// `argv`: rule name, the text to match, account id and path to move to
    /// (path `""` for no move), account id and path to copy to (path `""` for
    /// no copy), `true`/`false` for mark read, a flag index (`-1` for none),
    /// `true`/`false` for enabled. Replies `notarget`, `nocopytarget`,
    /// `taken`, `added`, or `unconfirmed`.
    ///
    /// Created DISABLED, given its condition, read back field by field, and
    /// only then switched on — a rule half-made by a script that failed midway
    /// is a rule that matches everything, and it must not be live while that
    /// is possible. Measured (macOS 27): a rule made with mark read, mark
    /// flagged, `mark flag index` 3 and a copy target reads back with exactly
    /// those, and delete / forward / redirect / reply empty.
    ///
    /// - Parameter field: Which header. A constant from ``RuleField``, never
    ///   a value.
    static func addRule(field: RuleField) -> String {
        """
        \(boxHandler)

        on run argv
            set vRuleName to item 1 of argv
            set vMatchText to item 2 of argv
            set vMoving to (item 4 of argv) is not ""
            set vCopying to (item 6 of argv) is not ""
            set vMarkRead to (item 7 of argv) is "true"
            set vFlagIndex to (item 8 of argv) as integer
            set vFlagging to vFlagIndex is not -1
            if vMoving and not my boxExists(item 3 of argv, item 4 of argv) then return "notarget"
            if vCopying and not my boxExists(item 5 of argv, item 6 of argv) then return "nocopytarget"
            tell application "Mail"
                if (count of (rules whose name is vRuleName)) is not 0 then return "taken"
                set vProps to {name:vRuleName, enabled:false, all conditions must be met:true, delete message:false, mark read:vMarkRead, mark flagged:vFlagging, stop evaluating rules:false}
                if vMoving then
                    set vProps to vProps & {should move message:true, move message:(my boxFor(item 3 of argv, item 4 of argv))}
                else
                    set vProps to vProps & {should move message:false}
                end if
                if vCopying then
                    set vProps to vProps & {should copy message:true, copy message:(my boxFor(item 5 of argv, item 6 of argv))}
                else
                    set vProps to vProps & {should copy message:false}
                end if
                set r to make new rule at end of rules with properties vProps
                if vFlagging then set mark flag index of r to vFlagIndex
                tell r to make new rule condition at end of rule conditions with properties {rule type:\(field.appleScriptType), qualifier:does contain value, expression:vMatchText}
                if (count of rule conditions of r) is not 1 then return "unconfirmed"
                if (expression of item 1 of rule conditions of r) is not vMatchText then return "unconfirmed"
                if delete message of r then return "unconfirmed"
                if (should move message of r) is not vMoving then return "unconfirmed"
                if (should copy message of r) is not vCopying then return "unconfirmed"
                if (mark read of r) is not vMarkRead then return "unconfirmed"
                if (mark flagged of r) is not vFlagging then return "unconfirmed"
                if vFlagging and (mark flag index of r) is not vFlagIndex then return "unconfirmed"
                if (forward message of r) is not "" then return "unconfirmed"
                if (redirect message of r) is not "" then return "unconfirmed"
                if (reply text of r) is not "" then return "unconfirmed"
                if (item 9 of argv) is "true" then set enabled of r to true
                return "added"
            end tell
        end run
        """
    }

    /// `argv`: rule name, `true`/`false`. Replies `norule`, `ambiguous`,
    /// `done` or `unconfirmed`. Measured: `enabled` reads back as set.
    static let setRuleEnabled = """
        on run argv
            set vWanted to ((item 2 of argv) is "true")
            tell application "Mail"
                set vHits to (rules whose name is (item 1 of argv))
                if (count of vHits) is 0 then return "norule"
                if (count of vHits) is not 1 then return "ambiguous"
                set r to item 1 of vHits
                set enabled of r to vWanted
                if (enabled of r) is vWanted then return "done"
                return "unconfirmed"
            end tell
        end run
        """

    // MARK: - Composing

    /// `argv`: account id, path, bare `Message-ID`, `true`/`false` for reply
    /// to all. Replies `missing` or `opened`.
    ///
    /// Measured: Mail opens a threaded reply with the subject and recipient
    /// filled in. Its `content` cannot be set from a script — writing it reads
    /// back empty — so this opens the reply and stops; there is no body.
    static let reply = """
        \(boxHandler)

        on run argv
            tell application "Mail"
                set vMatches to {}
                try
                    set vMatches to (messages of (my boxFor(item 1 of argv, item 2 of argv)) whose message id is (item 3 of argv))
                end try
                if (count of vMatches) is not 1 then return "missing"
                reply (item 1 of vMatches) opening window yes reply to all ((item 4 of argv) is "true")
                activate
                return "opened"
            end tell
        end run
        """

    /// `argv`: account id, path, bare `Message-ID`, then recipients. Replies
    /// `missing` or `opened`. Measured: recipients added this way read back.
    static let forward = """
        \(boxHandler)

        on run argv
            tell application "Mail"
                set vMatches to {}
                try
                    set vMatches to (messages of (my boxFor(item 1 of argv, item 2 of argv)) whose message id is (item 3 of argv))
                end try
                if (count of vMatches) is not 1 then return "missing"
                set f to forward (item 1 of vMatches) opening window yes
                tell f
                    repeat with i from 4 to (count of argv)
                        make new to recipient at end of to recipients with properties {address:(item i of argv)}
                    end repeat
                end tell
                activate
                return "opened"
            end tell
        end run
        """

    /// No `argv`. Asks every account to fetch.
    /// No `argv`. Replies `checked`, then the name of each account it
    /// synchronised, one a line. Measured: `synchronize` on an iCloud (IMAP)
    /// account returns at once; on a POP account it fails, which is skipped.
    static let checkForNewMail = """
        on run argv
            set vOut to "checked"
            tell application "Mail"
                check for new mail
                repeat with vAccount in (accounts whose enabled is true)
                    try
                        synchronize with vAccount
                        set vOut to vOut & linefeed & (name of vAccount)
                    end try
                end repeat
            end tell
            return vOut
        end run
        """
}
