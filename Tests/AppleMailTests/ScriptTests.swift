//
//  ScriptTests.swift
//  AppleMail
//
//  Created by David Sherlock on 2026.
//
//  The write side, WITHOUT Mail: every refusal is proven to happen before a
//  script runs, every reply shape is parsed, and every value is shown to
//  travel in argv rather than in source.
//

import Foundation
import XCTest
@testable import AppleMail

/// A runner that records what it was asked and replies with a canned answer.
private final class Recorder: @unchecked Sendable {
    var calls: [(source: String, arguments: [String])] = []
    var reply: String

    init(reply: String = "") { self.reply = reply }

    var runner: AppleScriptRunner {
        { source, arguments in
            self.calls.append((source, arguments))
            return self.reply
        }
    }
}

private let icloud = "00000000-0000-0000-0000-0000000000AA"

private func locator(_ id: String, _ path: String = "INBOX", account: String? = icloud) -> MessageLocator {
    MessageLocator(messageID: id, mailbox: MailboxReference(accountID: account, path: path))
}

final class MessageIDTests: XCTestCase {

    func testMailWantsTheBareForm() {
        // Measured on macOS 27: Mail's `message id` matched the bare value
        // once and the bracketed one never — the reason `mark` never worked.
        XCTAssertEqual(MessageIDs.bare("<abc@host.invalid>"), "abc@host.invalid")
        XCTAssertEqual(MessageIDs.bare("abc@host.invalid"), "abc@host.invalid")
        XCTAssertEqual(MessageIDs.bare("  <abc@host.invalid>\n"), "abc@host.invalid")
        XCTAssertEqual(locator("<abc@host.invalid>").messageID, "abc@host.invalid")
    }

    func testOnlyOneLineIdentifiersAreUsable() {
        XCTAssertTrue(MessageIDs.isUsable("<a@b>"))
        XCTAssertFalse(MessageIDs.isUsable("<>"))
        XCTAssertFalse(MessageIDs.isUsable("no-at-sign"))
        XCTAssertFalse(MessageIDs.isUsable("a@b\nend tell"))
    }

    func testTheLegacyMarkSendsTheBareForm() throws {
        let recorder = Recorder(reply: "changed")
        try MailScript.setRead(true, messageID: "<m1@host.invalid>", using: recorder.runner)
        XCTAssertEqual(recorder.calls.first?.arguments, ["m1@host.invalid", "true"])
    }
}

final class MailboxSafetyTests: XCTestCase {

    func testNothingGoesWhereMailEmptiesOrSends() {
        for path in ["Trash", "Deleted Messages", "Junk", "junk", "Spam", "Drafts", "Sent Messages",
                     "Outbox", "SendLater", "[Gmail]/Trash", "[Gmail]/All Mail"] {
            XCTAssertNotNil(MailboxSafety.refusalAsDestination(path), path)
        }
        for path in ["INBOX", "Archive", "Receipts/Shop", "Projects/Trash notes", "Accounting/Archive"] {
            XCTAssertNil(MailboxSafety.refusalAsDestination(path), path)
        }
    }

    func testMailsOwnMailboxesAreNeverRenamedOrRemoved() {
        for path in ["INBOX", "Inbox", "Archive", "Trash", "Sent Messages", "Drafts", "Junk", "Outbox"] {
            XCTAssertNotNil(MailboxSafety.refusalToChange(path), path)
        }
        XCTAssertNil(MailboxSafety.refusalToChange("Accounting/Archive"), "a folder of your own is yours")
    }

    func testPathsAreChecked() {
        XCTAssertNil(MailboxSafety.pathProblem("Accounting/Tax"))
        for bad in ["", " ", "/Tax", "Tax/", "a//b", "a/ /b", "tab\there"] {
            XCTAssertNotNil(MailboxSafety.pathProblem(bad), bad)
        }
        XCTAssertNotNil(MailboxSafety.newNameProblem("A/B"), "a rename keeps the folder where it is")
        XCTAssertNotNil(MailboxSafety.newNameProblem("Trash"))
        XCTAssertNil(MailboxSafety.newNameProblem("Tax Docs"))
    }
}

final class RefusedBeforeMailTests: XCTestCase {

    /// Each of these must throw WITHOUT the runner being called.
    func testRefusalsNeverReachMail() {
        let recorder = Recorder(reply: "ok\n")
        let cases: [() throws -> Void] = [
            { _ = try MailScript.move([locator("<a@b>")], to: MailboxReference(accountID: icloud, path: "Trash"),
                                      using: recorder.runner) },
            { _ = try MailScript.copy([locator("<a@b>")], to: MailboxReference(accountID: icloud, path: "Junk"),
                                      using: recorder.runner) },
            { _ = try MailScript.move([locator("not-an-id")], to: .onMyMac("Fine"), using: recorder.runner) },
            { _ = try MailScript.createMailbox(MailboxReference(accountID: icloud, path: "a//b"),
                                               using: recorder.runner) },
            { _ = try MailScript.createMailbox(MailboxReference(accountID: icloud, path: "Trash"),
                                               using: recorder.runner) },
            { try MailScript.renameMailbox(MailboxReference(accountID: icloud, path: "INBOX"), to: "X",
                                           using: recorder.runner) },
            { try MailScript.renameMailbox(.onMyMac("A/B"), to: "C/D", using: recorder.runner) },
            { try MailScript.addFilingRule(name: "x", field: .from, contains: "@", to: .onMyMac("A"),
                                           using: recorder.runner) },
            { try MailScript.addFilingRule(name: "x", field: .from, contains: "shop", to: .onMyMac("Trash"),
                                           using: recorder.runner) },
            { try MailScript.forward(locator("<a@b>"), to: ["not an address"], using: recorder.runner) },
        ]
        for (index, run) in cases.enumerated() {
            XCTAssertThrowsError(try run(), "case \(index)")
        }
        XCTAssertTrue(recorder.calls.isEmpty, "Mail was asked \(recorder.calls.count) times")
    }

    func testAnEmptyBatchAsksNothing() throws {
        let recorder = Recorder()
        XCTAssertEqual(try MailScript.move([], to: .onMyMac("A"), using: recorder.runner), [])
        XCTAssertTrue(recorder.calls.isEmpty)
    }
}

final class BatchTests: XCTestCase {

    func testValuesTravelInArgvNeverInSource() throws {
        let hostile = "Re: \" end tell\ndo shell script \"rm\""
        let recorder = Recorder(reply: "ok\nok\n")
        let messages = [locator("<one@host>", hostile), locator("<two@host>", "Receipts", account: nil)]
        let steps = try MailScript.move(messages, to: MailboxReference(accountID: icloud, path: "Receipts/Shop"),
                                        using: recorder.runner)
        XCTAssertEqual(steps, [.done, .done])

        let call = try XCTUnwrap(recorder.calls.first)
        XCTAssertFalse(call.source.contains("Shop"), "the destination is not in the script")
        XCTAssertFalse(call.source.contains("one@host"))
        XCTAssertFalse(call.source.contains("rm"))
        XCTAssertEqual(call.arguments, [
            "2", icloud, "Receipts/Shop",
            "2",
            icloud, hostile, "one@host",
            "", "Receipts", "two@host",
        ])
    }

    func testAMissingMessageMeansNothingWasDone() {
        XCTAssertThrowsError(try ScriptReplies.batchSteps("missing\n2:0\n3:-1\n", count: 3)) { error in
            guard case .scriptFailed(let text) = error as? MailError else { return XCTFail("\(error)") }
            XCTAssertTrue(text.contains("message 2: not found"), text)
            XCTAssertTrue(text.contains("message 3: its mailbox was not found"), text)
            XCTAssertTrue(text.contains("nothing was changed"), text)
        }
        XCTAssertThrowsError(try ScriptReplies.batchSteps("missing\n1:2\n", count: 1)) { error in
            guard case .scriptFailed(let text) = error as? MailError else { return XCTFail("\(error)") }
            XCTAssertTrue(text.contains("2 copies"), "an ambiguous match is refused too: \(text)")
        }
    }

    func testAMissingDestinationMeansNothingWasDone() {
        XCTAssertThrowsError(try ScriptReplies.batchSteps("notarget", count: 2, target: .onMyMac("Nope"))) { error in
            guard case .scriptFailed(let text) = error as? MailError else { return XCTFail("\(error)") }
            XCTAssertTrue(text.contains("On My Mac · Nope"), text)
        }
    }

    func testAFailureMidwaySaysWhichWereDoneAndWhichWereNot() throws {
        let steps = try ScriptReplies.batchSteps("ok\nfail:-10000:Mail got an error: nope", count: 4)
        XCTAssertEqual(steps, [.done, .failed("Mail got an error: nope"), .notAttempted, .notAttempted])
    }

    func testFlagColoursUseTheFlagIndex() throws {
        let recorder = Recorder(reply: "ok\n")
        _ = try MailScript.setFlag(true, color: .green, [locator("<a@b>")], using: recorder.runner)
        XCTAssertTrue(recorder.calls[0].source.contains("flag index"))
        XCTAssertEqual(Array(recorder.calls[0].arguments.prefix(2)), ["1", "3"])

        _ = try MailScript.setFlag(false, color: .green, [locator("<a@b>")], using: recorder.runner)
        XCTAssertTrue(recorder.calls[1].source.contains("flagged status"))
        XCTAssertEqual(Array(recorder.calls[1].arguments.prefix(2)), ["1", "false"])

        XCTAssertEqual(FlagColor(name: "Grey"), .gray)
        XCTAssertNil(FlagColor(name: "pink"))
    }
}

final class MailboxScriptTests: XCTestCase {

    func testCreateReportsWhatMailFound() throws {
        XCTAssertEqual(try MailScript.createMailbox(.onMyMac("A/B"), using: Recorder(reply: "created").runner), .created)
        XCTAssertEqual(try MailScript.createMailbox(.onMyMac("A/B"), using: Recorder(reply: "exists").runner),
                       .alreadyExists)
        XCTAssertThrowsError(try MailScript.createMailbox(.onMyMac("A"), using: Recorder(reply: "unconfirmed").runner))
    }

    /// Asking iCloud for `A/B` in one go, with no `A`, makes `A` a container
    /// that cannot hold mail — a move into it is accepted, then undone by the
    /// server. So each level is made on its own, and never the whole path.
    func testMailboxesAreMadeOneLevelAtATime() {
        let source = MailScriptSources.createMailbox
        XCTAssertTrue(source.contains("set vParts to text items of vThePath"))
        XCTAssertTrue(source.contains("with properties {name:vSoFar}"))
        XCTAssertFalse(source.contains("with properties {name:vThePath}"))
    }

    func testRenameKeepsTheParentAndRefusesATakenName() throws {
        let recorder = Recorder(reply: "renamed")
        let after = try MailScript.renameMailbox(MailboxReference(accountID: icloud, path: "Accounting/Tax"),
                                                 to: "Tax Docs", using: recorder.runner)
        XCTAssertEqual(after.path, "Accounting/Tax Docs")
        XCTAssertEqual(recorder.calls[0].arguments, [icloud, "Accounting/Tax", "Tax Docs", "Accounting/Tax Docs"])
        XCTAssertThrowsError(try MailScript.renameMailbox(.onMyMac("A"), to: "B", using: Recorder(reply: "taken").runner))
    }
}

final class RuleTests: XCTestCase {

    func testRulesAreReadWithEveryAction() {
        let fs = "\u{1F}", rs = "\u{1E}", item = "\u{1D}"
        let reply = "Shop\(fs)true\(fs)true\(fs)from header does contain value shop\(item)\(fs)move to Receipts/Shop\(item)\(rs)"
            + "Old\(fs)false\(fs)false\(fs)\(fs)delete\(item)forward to x@y\(item)\(rs)"
        let rules = ScriptReplies.rules(reply)
        XCTAssertEqual(rules.count, 2)
        XCTAssertEqual(rules[0], MailRule(name: "Shop", enabled: true, matchesAll: true,
                                          conditions: ["from header does contain value shop"],
                                          actions: ["move to Receipts/Shop"]))
        XCTAssertEqual(rules[1].actions, ["delete", "forward to x@y"])
        XCTAssertEqual(rules[1].conditions, [])
    }

    func testAFilingRuleOnlyFilesAndStartsSwitchedOff() throws {
        let recorder = Recorder(reply: "added")
        try MailScript.addFilingRule(name: "Shop", field: .from, contains: "shop.example",
                                     to: MailboxReference(accountID: icloud, path: "Receipts/Shop"),
                                     using: recorder.runner)
        let call = try XCTUnwrap(recorder.calls.first)
        XCTAssertEqual(call.arguments, ["Shop", "shop.example", icloud, "Receipts/Shop", "", "", "false", "-1", "true"])
        XCTAssertTrue(call.source.contains("enabled:false"), "made off, switched on only after the check")
        XCTAssertTrue(call.source.contains("delete message:false"))
        XCTAssertTrue(call.source.contains("rule type:from header"))
        XCTAssertFalse(call.source.contains("shop.example"), "the match text is argv")
        for word in ["forward message:\"", "redirect message:\"", "run script:"] {
            XCTAssertFalse(call.source.contains(word), word)
        }
    }

    func testARuleCanCopyMarkReadAndFlagButNeedsSomethingToDo() throws {
        let recorder = Recorder(reply: "added")
        try MailScript.addRule(name: "Bills", field: .subject, contains: "invoice",
                               actions: RuleActions(copyTo: .onMyMac("Bills"), markRead: true, flag: .green),
                               enabled: false, using: recorder.runner)
        XCTAssertEqual(recorder.calls[0].arguments,
                       ["Bills", "invoice", "", "", "", "Bills", "true", "3", "false"])
        let source = recorder.calls[0].source
        for check in ["(should copy message of r) is not vCopying", "(mark read of r) is not vMarkRead",
                      "(mark flag index of r) is not vFlagIndex", "(forward message of r) is not \"\"",
                      "(reply text of r) is not \"\""] {
            XCTAssertTrue(source.contains(check), "read back: \(check)")
        }
        XCTAssertThrowsError(try MailScript.addRule(name: "R", field: .from, contains: "shop", actions: RuleActions(),
                                                    using: Recorder().runner))
        XCTAssertThrowsError(try MailScript.addRule(name: "R", field: .from, contains: "shop",
                                                    actions: RuleActions(copyTo: .onMyMac("Junk")),
                                                    using: Recorder().runner))
    }

    func testOnlyARuleThatDoesNothingIrreversibleIsSwitchedOn() throws {
        let fs = "\u{1F}", rs = "\u{1E}", item = "\u{1D}"
        let listing = "Safe\(fs)false\(fs)true\(fs)\(fs)move to A\(item)mark read\(item)flag\(item)\(rs)"
            + "Risky\(fs)false\(fs)true\(fs)\(fs)move to A\(item)forward to x@y\(item)\(rs)"
        let recorder = Recorder(reply: "done")
        let runner: AppleScriptRunner = { source, arguments in
            let reply = try recorder.runner(source, arguments)
            return source.contains("repeat with r in rules") ? listing : reply
        }
        try MailScript.setRuleEnabled(true, name: "Safe", using: runner)
        XCTAssertEqual(recorder.calls.last?.arguments, ["Safe", "true"])
        XCTAssertThrowsError(try MailScript.setRuleEnabled(true, name: "Risky", using: runner)) {
            XCTAssertTrue("\($0)".contains("forward to x@y"), "\($0)")
        }
        XCTAssertEqual(recorder.calls.last?.arguments, [], "refused after the listing, before any change")
        try MailScript.setRuleEnabled(false, name: "Risky", using: runner)
        XCTAssertEqual(recorder.calls.last?.arguments, ["Risky", "false"], "switching off is always allowed")
        XCTAssertThrowsError(try MailScript.setRuleEnabled(true, name: "Nobody", using: runner))
        XCTAssertEqual(RuleSafety.unsafeActions(in: MailRule(name: "x", enabled: false, matchesAll: true,
            conditions: [], actions: ["delete", "copy to B", "run script", "reply", "redirect to z"])),
                       ["delete", "run script", "reply", "redirect to z"])
    }

    func testAFailedReadBackIsAnError() {
        XCTAssertThrowsError(try MailScript.addFilingRule(name: "R", field: .subject, contains: "invoice",
                                                          to: .onMyMac("A"), using: Recorder(reply: "unconfirmed").runner))
    }
}

final class ModelTests: XCTestCase {

    func testLocalMailboxesHaveNoAccount() {
        let local = Mailbox(id: 1, url: "local://AD38-0000/Inbox%20Test")
        XCTAssertTrue(local.isLocal)
        XCTAssertNil(local.accountID)
        XCTAssertEqual(local.reference, .onMyMac("Inbox Test"))

        let remote = Mailbox(id: 2, url: "imap://\(icloud)/Work/Invoices")
        XCTAssertFalse(remote.isLocal)
        XCTAssertEqual(remote.reference, MailboxReference(accountID: icloud, path: "Work/Invoices"))
    }

    func testAMessageKnowsWhereMailCanFindIt() {
        let message = Message(id: 1, messageID: "<a@b>", subject: "s", sender: Address(address: "x@y", name: nil),
                              sentAt: Date(), receivedAt: Date(), mailbox: "Receipts/Shop", accountID: icloud)
        XCTAssertEqual(message.locator, MessageLocator(messageID: "a@b",
                                                       mailbox: MailboxReference(accountID: icloud, path: "Receipts/Shop")))
        let noHeader = Message(id: 2, subject: "s", sender: Address(address: "x@y", name: nil),
                               sentAt: Date(), receivedAt: Date(), mailbox: "INBOX")
        XCTAssertNil(noHeader.locator)
    }

    func testReferencesKnowTheirParent() {
        XCTAssertEqual(MailboxReference.onMyMac("A/B/C").parent, "A/B")
        XCTAssertNil(MailboxReference.onMyMac("A").parent)
        XCTAssertEqual(MailboxReference.onMyMac("A/B").leaf, "B")
        XCTAssertEqual(ScriptReplies.renamedPath(.onMyMac("A"), to: "Z"), "Z")
    }
}

final class QueryOrderTests: XCTestCase {

    func testLargestFirstOrdersBySize() {
        XCTAssertTrue(QueryBuilder.sql(for: MailQuery(largestFirst: true)).sql.contains("order by m.size desc"))
        XCTAssertTrue(QueryBuilder.sql(for: MailQuery()).sql.contains("order by m.date_received desc"))
    }

    func testAutomatedIsMailsOwnClassification() {
        XCTAssertTrue(QueryBuilder.sql(for: MailQuery(isAutomated: true)).sql.contains("m.automated_conversation = 2"))
        XCTAssertTrue(QueryBuilder.sql(for: MailQuery(isAutomated: false)).sql.contains("m.automated_conversation != 2"))
    }
}

final class MailboxSpellingTests: XCTestCase {

    /// Measured against the index: `Trips/Hotel%20(Zu%CC%88rich)`.
    func testNamesMatchTheWayTheIndexSpellsThem() {
        let forms = QueryBuilder.mailboxSpellings("Trips/Hotel (Zürich)")
        XCTAssertTrue(forms.contains("Trips/Hotel%20(Zu%CC%88rich)"), "\(forms)")
        XCTAssertTrue(forms.contains("Trips/Hotel (Zürich)"))
        XCTAssertEqual(QueryBuilder.mailboxSpellings("Inbox Test")[1], "Inbox%20Test")
        XCTAssertEqual(Set(QueryBuilder.mailboxSpellings("INBOX")), ["INBOX"])
    }
}

final class DraftAndRefreshTests: XCTestCase {

    private func scratch() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("mail-draft-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    func testOnlyOrdinaryVisibleFilesAreAttached() throws {
        let folder = try scratch()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("p60.pdf")
        try Data("x".utf8).write(to: file)
        let hiddenFolder = folder.appendingPathComponent(".ssh")
        try FileManager.default.createDirectory(at: hiddenFolder, withIntermediateDirectories: true)
        let key = hiddenFolder.appendingPathComponent("id_ed25519")
        try Data("k".utf8).write(to: key)
        let hiddenFile = folder.appendingPathComponent(".env")
        try Data("e".utf8).write(to: hiddenFile)
        let link = folder.appendingPathComponent("innocent.pdf")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: key)

        XCTAssertNil(DraftSafety.attachmentProblem(file))
        XCTAssertNotNil(DraftSafety.attachmentProblem(key))
        XCTAssertNotNil(DraftSafety.attachmentProblem(hiddenFile))
        XCTAssertNotNil(DraftSafety.attachmentProblem(link), "a link is judged by where it points")
        XCTAssertNotNil(DraftSafety.attachmentProblem(folder), "a folder")
        XCTAssertNotNil(DraftSafety.attachmentProblem(folder.appendingPathComponent("missing.pdf")))

        let recorder = Recorder(reply: "drafted")
        XCTAssertThrowsError(try MailScript.draft(to: ["a@b.invalid"], subject: "s", body: "b",
                                                  attachments: [file, key], using: recorder.runner))
        XCTAssertTrue(recorder.calls.isEmpty, "refused before Mail is asked")
        try MailScript.draft(to: ["a@b.invalid"], subject: "s", body: "b", attachments: [file], using: recorder.runner)
        XCTAssertEqual(recorder.calls[0].arguments.last, file.standardizedFileURL.path)
        XCTAssertFalse(recorder.calls[0].source.contains("p60"), "the path is argv")
        XCTAssertFalse(recorder.calls[0].source.contains(" send"), "the draft script never sends")
        XCTAssertThrowsError(try MailScript.draft(to: ["a@b.invalid"], subject: "s", body: "b", attachments: [file],
                                                  using: Recorder(reply: "attached 0").runner))
    }

    func testRefreshReportsTheAccountsItSynced() throws {
        XCTAssertEqual(try MailScript.checkForNewMail(using: Recorder(reply: "checked\niCloud").runner), ["iCloud"])
        XCTAssertEqual(try MailScript.checkForNewMail(using: Recorder(reply: "checked").runner), [])
        XCTAssertThrowsError(try MailScript.checkForNewMail(using: Recorder(reply: "").runner))
    }
}
