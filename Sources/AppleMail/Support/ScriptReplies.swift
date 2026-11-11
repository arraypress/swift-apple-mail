//
//  ScriptReplies.swift
//  AppleMail
//
//  Created by David Sherlock on 2026.
//
//  Turning what a script printed into what happened — pure functions, so
//  every reply shape is tested without Mail.
//

import Foundation

enum ScriptReplies {

    /// The `argv` of a batch: operation arguments, then each message as
    /// account id, path, `Message-ID`.
    static func batchArguments(operation: [String], messages: [MessageLocator]) -> [String] {
        var arguments = [String(operation.count)] + operation + [String(messages.count)]
        for locator in messages {
            arguments += [locator.mailbox.accountID ?? "", locator.mailbox.path, locator.messageID]
        }
        return arguments
    }

    /// What a batch did to each message, in order.
    ///
    /// - Throws: ``MailError/scriptFailed(_:)`` when the batch refused before
    ///   doing anything — no destination, or messages that were not there.
    static func batchSteps(_ reply: String, count: Int, target: MailboxReference? = nil) throws -> [ScriptStep] {
        let lines = reply.split(whereSeparator: \.isNewline).map(String.init)
        if lines.first == "notarget" {
            let name = target?.described ?? "the destination"
            throw MailError.scriptFailed("no mailbox \(name) — nothing was changed")
        }
        if lines.first == "missing" {
            let detail = lines.dropFirst().compactMap { line -> String? in
                let parts = line.split(separator: ":")
                guard parts.count == 2, let index = Int(parts[0]), let found = Int(parts[1]) else { return nil }
                let what = found < 0 ? "its mailbox was not found" : found == 0 ? "not found" : "\(found) copies"
                return "message \(index): \(what)"
            }
            throw MailError.scriptFailed(
                "Mail could not find every message (\(detail.joined(separator: "; "))) — nothing was changed"
            )
        }
        var steps: [ScriptStep] = []
        for line in lines {
            if line == "ok" {
                steps.append(.done)
            } else if line.hasPrefix("fail:") {
                let words = line.dropFirst("fail:".count).split(separator: ":", maxSplits: 1)
                steps.append(.failed(words.count == 2 ? String(words[1]) : String(line.dropFirst(5))))
                break
            }
        }
        while steps.count < count { steps.append(.notAttempted) }
        return Array(steps.prefix(count))
    }

    /// The rules in a listing.
    static func rules(_ reply: String) -> [MailRule] {
        reply.split(separator: MailScriptSources.recordSeparator, omittingEmptySubsequences: true).compactMap { record in
            let fields = record.split(separator: MailScriptSources.fieldSeparator, omittingEmptySubsequences: false)
                .map(String.init)
            guard fields.count >= 5 else { return nil }
            func items(_ text: String) -> [String] {
                text.split(separator: MailScriptSources.itemSeparator).map(String.init)
            }
            return MailRule(
                name: fields[0],
                enabled: fields[1] == "true",
                matchesAll: fields[2] == "true",
                conditions: items(fields[3]),
                actions: items(fields[4])
            )
        }
    }

    /// The path a mailbox will have after its last component is renamed.
    static func renamedPath(_ reference: MailboxReference, to name: String) -> String {
        reference.parent.map { "\($0)/\(name)" } ?? name
    }
}
