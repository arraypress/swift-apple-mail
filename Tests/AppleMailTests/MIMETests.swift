//
//  MIMETests.swift
//  AppleMail
//
//  Created by David Sherlock on 2026.
//
//  Every fixture here is written by hand. Nothing in this suite reads the
//  machine's mail: a test that needs somebody's inbox proves nothing on
//  anybody else's, and these are the rules that decide whether a letter comes
//  out readable.
//

import XCTest
@testable import AppleMail

final class HeaderTests: XCTestCase {

    func testFoldedHeadersAreJoined() {
        // Long To and Subject lines are folded as a matter of course, and a
        // parser that starts a new header on the continuation loses the rest.
        let raw = Data("""
            Subject: a subject that was
             folded across two lines
            From: ada@example.invalid

            """.utf8)
        let headers = MIME.parseHeaders(raw)
        XCTAssertEqual(
            headers.first { $0.name == "Subject" }?.value,
            "a subject that was folded across two lines"
        )
        XCTAssertEqual(headers.first { $0.name == "From" }?.value, "ada@example.invalid")
    }

    func testHeadersAreFoundWhateverTheirCase() {
        let part = MIME.parse(Data("content-type: text/plain\r\n\r\nbody".utf8))
        XCTAssertEqual(part.header("Content-Type"), "text/plain")
        XCTAssertEqual(part.contentType, "text/plain")
    }

    func testBothLineEndingsSplitHeadersFromBody() {
        // Mail keeps CRLF as it arrived; a message through a gateway may be
        // LF-only, and knowing one of them reads the whole letter as headers.
        for separator in ["\r\n\r\n", "\n\n"] {
            let part = MIME.parse(Data("Subject: hello\(separator)the body".utf8))
            XCTAssertEqual(part.header("Subject"), "hello")
            XCTAssertEqual(String(decoding: part.body, as: UTF8.self), "the body")
        }
    }

    func testParametersAreReadWithAndWithoutQuotes() {
        let part = MIME.parse(Data("""
            Content-Type: multipart/mixed; boundary="a-boundary"

            """.utf8))
        XCTAssertEqual(part.parameter("boundary", of: "Content-Type"), "a-boundary")

        let bare = MIME.parse(Data("Content-Type: text/plain; charset=utf-8\r\n\r\n".utf8))
        XCTAssertEqual(bare.parameter("charset", of: "Content-Type"), "utf-8")
    }
}

final class DecodingTests: XCTestCase {

    func testQuotedPrintableDecodesBytes() {
        let decoded = MIME.quotedPrintable(Data("Ren=C3=A9 =E2=80=94 caf=C3=A9".utf8))
        XCTAssertEqual(String(decoding: decoded, as: UTF8.self), "René — café")
    }

    func testASoftLineBreakDisappears() {
        // "=" at end of line means the line continues. Keeping it puts an
        // equals sign in the middle of a word.
        let decoded = MIME.quotedPrintable(Data("this is one =\r\nsentence".utf8))
        XCTAssertEqual(String(decoding: decoded, as: UTF8.self), "this is one sentence")
    }

    func testEncodedWordsInSubjects() {
        XCTAssertEqual(MIME.decodeWords("=?UTF-8?Q?Ren=C3=A9?="), "René")
        XCTAssertEqual(MIME.decodeWords("=?UTF-8?B?SGVsbG8gd29ybGQ=?="), "Hello world")
    }

    func testAnUnderscoreIsASpaceInsideAnEncodedWord() {
        // Only inside an encoded word. This one catches a decoder that reuses
        // plain quoted-printable and renders every space as an underscore.
        XCTAssertEqual(MIME.decodeWords("=?UTF-8?Q?your_invoice?="), "your invoice")
    }

    func testTextAroundAnEncodedWordSurvives() {
        XCTAssertEqual(
            MIME.decodeWords("Re: =?UTF-8?Q?caf=C3=A9?= opening hours"),
            "Re: café opening hours"
        )
    }

    func testAMalformedEncodedWordIsLeftAlone() {
        // Better a subject showing its own encoding than a subject silently
        // emptied.
        XCTAssertEqual(MIME.decodeWords("=?UTF-8?Z?nonsense?="), "=?UTF-8?Z?nonsense?=")
        XCTAssertEqual(MIME.decodeWords("=?broken"), "=?broken")
    }

    func testPlainTextIsUntouched() {
        XCTAssertEqual(MIME.decodeWords("an ordinary subject"), "an ordinary subject")
    }

    func testCharsetsBeyondTheHardcodedFew() throws {
        // A Japanese mail decoded as UTF-8 is a page of replacement characters,
        // so the lookup falls through to CoreFoundation rather than guessing.
        XCTAssertEqual(MIME.encoding(named: "utf-8"), .utf8)
        XCTAssertEqual(MIME.encoding(named: "ISO-8859-1"), .isoLatin1)
        XCTAssertEqual(MIME.encoding(named: "nonsense-charset"), .utf8)

        // Asserted by round trip rather than by raw value: the point is that a
        // Japanese mail comes out as Japanese, not that the constant has a
        // particular number.
        let shiftJIS = MIME.encoding(named: "shift_jis")
        XCTAssertNotEqual(shiftJIS, .utf8, "shift_jis must not fall back to UTF-8")
        let japanese = "こんにちは"
        let encoded = try XCTUnwrap(japanese.data(using: shiftJIS))
        XCTAssertEqual(String(data: encoded, encoding: shiftJIS), japanese)
        XCTAssertNotEqual(
            String(data: encoded, encoding: .utf8), japanese,
            "if UTF-8 could read these bytes the test would prove nothing"
        )
    }

    func testBase64BodiesDecode() {
        let part = MIME.parse(Data("""
            Content-Type: text/plain\r
            Content-Transfer-Encoding: base64\r
            \r
            SGVsbG8gd29ybGQ=
            """.utf8))
        XCTAssertEqual(MIME.text(of: part), "Hello world")
    }
}

final class MultipartTests: XCTestCase {

    private let message = Data("""
        Content-Type: multipart/mixed; boundary="BOUND"\r
        Subject: with an attachment\r
        \r
        --BOUND\r
        Content-Type: text/plain; charset=utf-8\r
        \r
        the readable part\r
        --BOUND\r
        Content-Type: application/pdf; name="invoice.pdf"\r
        Content-Disposition: attachment; filename="invoice.pdf"\r
        Content-Transfer-Encoding: base64\r
        \r
        SGVsbG8=\r
        --BOUND--\r
        """.utf8)

    func testPartsAreSeparated() {
        let part = MIME.parse(message)
        XCTAssertEqual(part.parts.count, 2)
        XCTAssertEqual(part.parts[0].contentType, "text/plain")
        XCTAssertEqual(part.parts[1].contentType, "application/pdf")
    }

    func testTheTextPartIsTheLetter() throws {
        let body = try MailStore.body(ofMessage: 1, emlx: emlx(message))
        XCTAssertEqual(body.text, "the readable part")
        XCTAssertFalse(body.fromHTML)
    }

    func testAttachmentsAreNamedAndDecoded() throws {
        let body = try MailStore.body(ofMessage: 1, emlx: emlx(message), includeAttachmentData: true)
        XCTAssertEqual(body.attachments.count, 1)
        XCTAssertEqual(body.attachments[0].name, "invoice.pdf")
        XCTAssertEqual(body.attachments[0].contentType, "application/pdf")
        XCTAssertEqual(body.attachments[0].data.map { String(decoding: $0, as: UTF8.self) }, "Hello")
    }

    func testAttachmentBytesAreNotLoadedUnlessAsked() throws {
        let body = try MailStore.body(ofMessage: 1, emlx: emlx(message))
        XCTAssertEqual(body.attachments.count, 1)
        XCTAssertNil(body.attachments[0].data, "a listing must not read 477 MB of attachments")
    }

    func testHTMLIsUsedOnlyWhenThereIsNoPlainPart() throws {
        let htmlOnly = Data("""
            Content-Type: multipart/alternative; boundary="B"\r
            \r
            --B\r
            Content-Type: text/html\r
            \r
            <p>hello <b>there</b></p>\r
            --B--\r
            """.utf8)
        let body = try MailStore.body(ofMessage: 2, emlx: emlx(htmlOnly))
        XCTAssertTrue(body.fromHTML)
        XCTAssertEqual(body.text, "hello there")
    }

    /// Wraps a message the way Mail stores it: a length line, then the message.
    private func emlx(_ message: Data) -> Data {
        var data = Data("\(message.count)\n".utf8)
        data.append(message)
        data.append(Data("<?xml version=\"1.0\"?><plist><dict/></plist>".utf8))
        return data
    }
}

final class EmlxTests: XCTestCase {

    func testTheLengthLineDecidesWhereTheMessageEnds() throws {
        // Mail's bookkeeping plist follows the message and contains colons and
        // angle brackets of its own. Scanning for the end instead of trusting
        // the count is how a plist ends up rendered as the last paragraph.
        let message = "Subject: hi\r\n\r\nbody text"
        var data = Data("\(message.utf8.count)\n".utf8)
        data.append(Data(message.utf8))
        data.append(Data("<?xml version=\"1.0\"?><plist><dict><key>flags</key></dict></plist>".utf8))

        let extracted = try Emlx.split(data)
        XCTAssertEqual(String(decoding: extracted, as: UTF8.self), message)
    }

    func testAFileWithNoLengthLineIsRefused() {
        XCTAssertThrowsError(try Emlx.split(Data("no newline here".utf8)))
        XCTAssertThrowsError(try Emlx.split(Data("not a number\nbody".utf8)))
    }

    func testALengthLongerThanTheFileDoesNotCrash() {
        // A truncated download should be a short message, not a trap.
        var data = Data("99999\n".utf8)
        data.append(Data("Subject: hi\r\n\r\nshort".utf8))
        XCTAssertNoThrow(try Emlx.split(data))
    }
}
