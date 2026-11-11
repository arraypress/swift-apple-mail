//
//  RuleSafety.swift
//  AppleMail
//
//  Created by David Sherlock on 2026.
//
//  What a rule may do before this library will make it, or switch it on.
//

import Foundation

/// The checks a rule passes before Mail is asked to make it or switch it on.
public enum RuleSafety {

    /// The actions, as ``MailRule/actions`` words them, that a rule may have
    /// and still be switched on here. Anything else — deleting, forwarding,
    /// redirecting, replying, running a script — sends or destroys mail with
    /// nobody watching, so such a rule is switched on in Mail by a person.
    static let safeActionPrefixes = ["move to ", "copy to ", "mark read", "flag", "stop evaluating rules"]

    /// The actions in a rule that this library will not switch on, in the
    /// order Mail lists them. Empty when every action is safe.
    public static func unsafeActions(in rule: MailRule) -> [String] {
        rule.actions.filter { action in
            !safeActionPrefixes.contains { action.hasPrefix($0) }
        }
    }

    /// Why a rule cannot be made as described, or `nil` when it can.
    public static func problem(name: String, text: String, actions: RuleActions) -> String? {
        if name.trimmingCharacters(in: .whitespaces).isEmpty { return "a rule needs a name" }
        if name.contains(where: \.isNewline) || text.contains(where: \.isNewline) {
            return "a rule's name and match text are one line each"
        }
        if text.trimmingCharacters(in: .whitespaces).count < 3 {
            return "match on at least three characters, so the rule cannot catch everything"
        }
        if actions.moveTo == nil, actions.copyTo == nil, !actions.markRead, actions.flag == nil {
            return "a rule needs something to do: move, copy, mark read or flag"
        }
        for destination in [actions.moveTo, actions.copyTo].compactMap({ $0 }) {
            if let refusal = MailboxSafety.refusalAsDestination(destination.path) { return refusal }
            if let problem = MailboxSafety.pathProblem(destination.path) { return problem }
        }
        return nil
    }

    /// The actions as a person reads them: `move to Receipts`, `flag green`.
    public static func describe(_ actions: RuleActions) -> [String] {
        var words: [String] = []
        if let moveTo = actions.moveTo { words.append("move to \(moveTo.described)") }
        if let copyTo = actions.copyTo { words.append("copy to \(copyTo.described)") }
        if actions.markRead { words.append("mark read") }
        if let flag = actions.flag { words.append("flag \(flag.name)") }
        return words
    }
}
