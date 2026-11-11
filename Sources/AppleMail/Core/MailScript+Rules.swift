//
//  MailScript+Rules.swift
//  AppleMail
//
//  Created by David Sherlock on 2026.
//
//  Reading Mail's rules, and adding the one kind this library will make: a
//  rule that files.
//

import Foundation

public extension MailScript {

    /// Every rule, with every action Mail reports for it.
    static func rules(using runner: AppleScriptRunner) throws -> [MailRule] {
        ScriptReplies.rules(try runner(MailScriptSources.listRules, []))
    }

    /// Adds a rule that moves matching incoming mail into a mailbox, and does
    /// nothing else.
    ///
    /// There is no parameter for deleting, forwarding, redirecting, replying
    /// or running a script: a rule acts on mail nobody has seen yet, with
    /// nobody watching, so the only action offered is one that can be undone
    /// by moving the message back.
    ///
    /// - Parameters:
    ///   - name: The rule's name. Must not already be taken.
    ///   - field: The header to match.
    ///   - text: What the header must contain. At least three characters, so a
    ///     typo cannot become a rule that files everything.
    ///   - destination: Where matching mail goes.
    ///   - enabled: Whether it is switched on once made.
    static func addFilingRule(name: String, field: RuleField, contains text: String,
                              to destination: MailboxReference, enabled: Bool = true,
                              using runner: AppleScriptRunner) throws {
        if let problem = filingRuleProblem(name: name, text: text, destination: destination) {
            throw MailError.scriptFailed(problem)
        }
        let reply = try runner(MailScriptSources.addFilingRule(field: field),
                               [name, text, destination.accountID ?? "", destination.path, enabled ? "true" : "false"])
        switch reply {
        case "added": return
        case "notarget": throw MailError.scriptFailed("no mailbox \(destination.described) — no rule was made")
        case "taken": throw MailError.scriptFailed("a rule called \(name) already exists — no rule was made")
        default:
            throw MailError.scriptFailed(
                "the rule \(name) was made but did not read back as asked; it was left switched OFF — check it in Mail ▸ Settings ▸ Rules"
            )
        }
    }

    /// Why a filing rule cannot be made as described, or `nil` when it can.
    static func filingRuleProblem(name: String, text: String, destination: MailboxReference) -> String? {
        if name.trimmingCharacters(in: .whitespaces).isEmpty { return "a rule needs a name" }
        if name.contains(where: \.isNewline) || text.contains(where: \.isNewline) {
            return "a rule's name and match text are one line each"
        }
        if text.trimmingCharacters(in: .whitespaces).count < 3 {
            return "match on at least three characters, so the rule cannot catch everything"
        }
        if let refusal = MailboxSafety.refusalAsDestination(destination.path) { return refusal }
        return MailboxSafety.pathProblem(destination.path)
    }
}
