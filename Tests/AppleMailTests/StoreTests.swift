//
//  StoreTests.swift
//  AppleMail
//
//  Created by David Sherlock on 2026.
//

import XCTest
@testable import AppleMail

final class MailboxTests: XCTestCase {

    func testAnAccountAddressNeverSurvivesIntoAMailbox() {
        // The URL carries the account's email address in its user component.
        // A listing that printed it would put somebody's address in every row,
        // so it is dropped at parse time rather than hidden at print time —
        // a value that is never stored cannot leak into a log or a payload.
        let box = Mailbox(id: 1, url: "imap://ada%40example.invalid@imap.example.invalid/INBOX")
        XCTAssertEqual(box.account, "imap.example.invalid")
        XCTAssertEqual(box.name, "INBOX")
        XCTAssertFalse(box.described.contains("ada"))
        XCTAssertFalse(box.described.contains("@example.invalid/"))
    }

    func testNestedFoldersKeepTheirPath() {
        let box = Mailbox(id: 1, url: "imap://x@host.invalid/INBOX/Receipts/2026")
        XCTAssertEqual(box.name, "INBOX/Receipts/2026")
    }

    func testPercentEncodedFolderNamesAreReadable() {
        let box = Mailbox(id: 1, url: "imap://x@host.invalid/Sent%20Messages")
        XCTAssertEqual(box.name, "Sent Messages")
    }

    func testLocalMailboxes() {
        let box = Mailbox(id: 1, url: "local://localhost/Notes")
        XCTAssertEqual(box.name, "Notes")
    }

    func testTheFoldersMailLeavesFromAreNotIncoming() {
        // A search for "everything from Ada" that returns your own replies to
        // Ada is answering a different question.
        for name in ["Sent Messages", "Drafts", "Trash", "INBOX/Sent"] {
            let box = Mailbox(id: 1, url: "imap://x@host.invalid/\(name.replacingOccurrences(of: " ", with: "%20"))")
            XCTAssertFalse(box.isIncoming, "\(name) should not count as incoming")
        }
        for name in ["INBOX", "Archive", "INBOX/Receipts"] {
            let box = Mailbox(id: 1, url: "imap://x@host.invalid/\(name)")
            XCTAssertTrue(box.isIncoming, "\(name) should count as incoming")
        }
    }
}

final class AddressTests: XCTestCase {

    func testABlankDisplayNameIsNoName() {
        // Mail stores an empty comment rather than none, and a caller should
        // never have to test for a blank string.
        XCTAssertNil(Address(address: "a@b.invalid", name: "").name)
        XCTAssertNil(Address(address: "a@b.invalid", name: "   ").name)
        XCTAssertEqual(Address(address: "a@b.invalid", name: "  Ada  ").name, "Ada")
    }

    func testDomainIsWhatComesAfterTheLastAt() {
        XCTAssertEqual(Address(address: "ada@example.invalid").domain, "example.invalid")
        // Quoted local parts can contain an @; the last one wins.
        XCTAssertEqual(Address(address: "\"odd@name\"@example.invalid").domain, "example.invalid")
        XCTAssertEqual(Address(address: "not-an-address").domain, "")
    }

    func testDescribedFallsBackToTheAddress() {
        XCTAssertEqual(Address(address: "a@b.invalid").described, "a@b.invalid")
        XCTAssertEqual(Address(address: "a@b.invalid", name: "Ada").described, "Ada <a@b.invalid>")
    }
}

final class QueryTests: XCTestCase {

    func testEveryValueIsBoundRatherThanPasted() {
        // The one rule that matters here: a subject line is somebody else's
        // text, and it must never reach the statement.
        let (sql, values) = QueryBuilder.sql(for: MailQuery(text: "'; drop table messages --"))
        XCTAssertFalse(sql.contains("drop table"))
        XCTAssertTrue(sql.contains("?"))
        XCTAssertEqual(values.count, 4, "three text matches and the limit")
    }

    func testSQLWildcardsInASearchAreEscaped() {
        // "100% off" and "one_two" occur in real subject lines, and unescaped
        // they would quietly match everything.
        let (_, values) = QueryBuilder.clauses(for: MailQuery(subject: "100% off_now"))
        guard case .text(let bound)? = values.first else { return XCTFail("nothing bound") }
        XCTAssertEqual(bound, "%100\\% off\\_now%")
    }

    func testDeletedMessagesAreAlwaysExcluded() {
        let (clause, _) = QueryBuilder.clauses(for: MailQuery())
        XCTAssertTrue(clause.contains("m.deleted = 0"))
    }

    func testDatesAreBoundAsUnixSeconds() {
        // Mail stores plain Unix seconds — not the 2001 epoch Core Data uses
        // elsewhere on this system. Measured against a live index: the oldest
        // row read back as 2010 and the newest as today.
        let moment = Date(timeIntervalSince1970: 1_700_000_000)
        let (_, values) = QueryBuilder.clauses(for: MailQuery(since: moment))
        guard case .integer(let bound)? = values.first else { return XCTFail("nothing bound") }
        XCTAssertEqual(bound, 1_700_000_000)
    }

    func testAnEmptyQueryIsRecognisable() {
        XCTAssertTrue(MailQuery().isEmpty)
        XCTAssertFalse(MailQuery(text: "hello").isEmpty)
        XCTAssertTrue(MailQuery(limit: 10).isEmpty, "a limit does not narrow anything")
    }
}

final class HTMLTests: XCTestCase {

    func testMarkupBecomesText() {
        XCTAssertEqual(HTMLText.from("<p>hello <b>there</b></p>"), "hello there")
    }

    func testScriptAndStyleContentIsDropped() {
        // Otherwise a marketing email reads as a stylesheet.
        let html = "<style>.a{color:red}</style><p>real text</p><script>var x=1;</script>"
        XCTAssertEqual(HTMLText.from(html), "real text")
    }

    func testAStyleContainingAnAngleBracketDoesNotEndEarly() {
        let html = "<style>a > b { color: red }</style><p>real text</p>"
        XCTAssertEqual(HTMLText.from(html), "real text")
    }

    func testBlockElementsBecomeLineBreaks() {
        XCTAssertEqual(HTMLText.from("<div>one</div><div>two</div>"), "one\ntwo")
        XCTAssertEqual(HTMLText.from("one<br>two"), "one\ntwo")
    }

    func testEntitiesAreResolved() {
        XCTAssertEqual(HTMLText.from("<p>Tom &amp; Jerry &mdash; &pound;5</p>"), "Tom & Jerry — £5")
        XCTAssertEqual(HTMLText.from("<p>it&#39;s &#x2019;s</p>"), "it's ’s")
    }

    func testRunsOfBlankLinesCollapse() {
        // An HTML mail is mostly layout; the naive strip leaves dozens of
        // blank lines behind. One survives as a paragraph break; the rest go.
        XCTAssertEqual(HTMLText.from("<div>a</div><div></div><div></div><div>b</div>"), "a\n\nb")
        XCTAssertEqual(HTMLText.from("<p>a</p>" + String(repeating: "<br>", count: 9) + "<p>b</p>"),
                       "a\n\nb")
    }

    func testAnUnclosedTagDoesNotSwallowTheMessage() {
        XCTAssertEqual(HTMLText.from("<p>text<"), "text")
    }
}

final class ScriptTests: XCTestCase {

    func testAppleScriptLiteralsEscapeInTheRightOrder() {
        // Backslashes first, then quotes. The other order double-escapes and
        // turns a subject containing a quotation mark into script.
        XCTAssertEqual(MailScript.literal(#"say "hi""#), #""say \"hi\"""#)
        XCTAssertEqual(MailScript.literal(#"back\slash"#), #""back\\slash""#)
    }

    func testAnAddressThatIsNotOneIsRefused() {
        // A quotation mark in an address would end the literal and change the
        // meaning of the script.
        XCTAssertThrowsError(try MailScript.draft(to: ["not an address"], subject: "s", body: "b"))
        XCTAssertThrowsError(try MailScript.draft(to: [#"a"@b.invalid"#], subject: "s", body: "b"))
    }

    func testOnlyARealMessageIDCanBeMarked() {
        XCTAssertThrowsError(try MailScript.setFlagged(true, messageID: "1234"))
        XCTAssertThrowsError(try MailScript.setRead(true, messageID: #"<a"b@c>"#))
    }
}
