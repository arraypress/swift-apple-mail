//
//  MailScript+Rules.swift
//  AppleMail
//
//  Created by David Sherlock on 2026.
//
//  Reading Mail's rules, adding the kinds this library will make — rules
//  that file, copy, mark read or flag — and switching rules on and off.
//

import Foundation

public extension MailScript {

    /// Every rule, with every action Mail reports for it.
    static func rules(using runner: AppleScriptRunner) throws -> [MailRule] {
        ScriptReplies.rules(try runner(MailScriptSources.listRules, []))
    }

    /// Adds a rule that moves matching incoming mail into a mailbox, and does
    /// nothing else. The same as ``addRule(name:field:contains:actions:enabled:using:)``
    /// with only a move.
    static func addFilingRule(name: String, field: RuleField, contains text: String,
                              to destination: MailboxReference, enabled: Bool = true,
                              using runner: AppleScriptRunner) throws {
        try addRule(name: name, field: field, contains: text, actions: RuleActions(moveTo: destination),
                    enabled: enabled, using: runner)
    }

    /// Adds a rule that matches one header and moves, copies, marks read or
    /// flags matching incoming mail — any of those, and nothing else.
    ///
    /// There is no parameter for deleting, forwarding, redirecting, replying
    /// or running a script: a rule acts on mail nobody has seen yet, with
    /// nobody watching, so it may only do what a person can put back.
    ///
    /// The rule is made switched off, read back field by field, and only then
    /// switched on. If the read-back disagrees, it is left off and this throws.
    ///
    /// - Parameters:
    ///   - name: The rule's name. Must not already be taken.
    ///   - field: The header to match.
    ///   - text: What the header must contain. At least three characters, so a
    ///     typo cannot become a rule that catches everything.
    ///   - actions: What it does. At least one.
    ///   - enabled: Whether it is switched on once made and checked.
    static func addRule(name: String, field: RuleField, contains text: String, actions: RuleActions,
                        enabled: Bool = true, using runner: AppleScriptRunner) throws {
        if let problem = RuleSafety.problem(name: name, text: text, actions: actions) {
            throw MailError.scriptFailed(problem)
        }
        let reply = try runner(MailScriptSources.addRule(field: field), [
            name, text,
            actions.moveTo?.accountID ?? "", actions.moveTo?.path ?? "",
            actions.copyTo?.accountID ?? "", actions.copyTo?.path ?? "",
            actions.markRead ? "true" : "false",
            String(actions.flag?.rawValue ?? -1),
            enabled ? "true" : "false",
        ])
        switch reply {
        case "added": return
        case "notarget":
            throw MailError.scriptFailed("no mailbox \(actions.moveTo?.described ?? "") — no rule was made")
        case "nocopytarget":
            throw MailError.scriptFailed("no mailbox \(actions.copyTo?.described ?? "") — no rule was made")
        case "taken": throw MailError.scriptFailed("a rule called \(name) already exists — no rule was made")
        default:
            throw MailError.scriptFailed(
                "the rule \(name) was made but did not read back as asked; it was left switched OFF — check it in Mail ▸ Settings ▸ Rules"
            )
        }
    }

    /// Why a filing rule cannot be made as described, or `nil` when it can.
    static func filingRuleProblem(name: String, text: String, destination: MailboxReference) -> String? {
        RuleSafety.problem(name: name, text: text, actions: RuleActions(moveTo: destination))
    }

    /// Switches a rule on or off, found by its exact name.
    ///
    /// Switching off is always allowed. Switching on is refused for a rule
    /// that deletes, forwards, redirects, replies or runs a script — see
    /// ``RuleSafety/unsafeActions(in:)`` — because that would let mail be
    /// sent or destroyed with nobody watching. Such a rule is switched on in
    /// Mail by a person.
    static func setRuleEnabled(_ enabled: Bool, name: String, using runner: AppleScriptRunner) throws {
        if enabled {
            let named = try rules(using: runner).filter { $0.name == name }
            guard named.count == 1, let rule = named.first else {
                throw MailError.scriptFailed(named.isEmpty
                    ? "no rule called \(name)"
                    : "\(named.count) rules are called \(name) — rename one in Mail first")
            }
            let unsafe = RuleSafety.unsafeActions(in: rule)
            guard unsafe.isEmpty else {
                throw MailError.scriptFailed(
                    "\(name) would \(unsafe.joined(separator: ", ")) — switch it on in Mail if you mean it; it was not changed"
                )
            }
        }
        switch try runner(MailScriptSources.setRuleEnabled, [name, enabled ? "true" : "false"]) {
        case "done": return
        case "norule": throw MailError.scriptFailed("no rule called \(name)")
        case "ambiguous": throw MailError.scriptFailed("more than one rule is called \(name) — rename one in Mail first")
        default: throw MailError.scriptFailed("Mail did not report \(name) as switched \(enabled ? "on" : "off") — check it in Mail ▸ Settings ▸ Rules")
        }
    }
}
