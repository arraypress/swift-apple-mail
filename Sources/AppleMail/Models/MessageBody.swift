//
//  MessageBody.swift
//  AppleMail
//
//  Created by David Sherlock on 2026.
//

import Foundation

/// The letter itself, once it has been read off disk.
public struct MessageBody: Sendable, Equatable {

    /// The message this belongs to.
    public let messageID: Int64

    /// The readable text: the plain-text part when the sender wrote one,
    /// otherwise the HTML part with its markup removed.
    public let text: String

    /// Whether ``text`` came from HTML rather than a plain-text part.
    public let fromHTML: Bool

    /// Headers as they appeared, decoded out of RFC 2047 where needed.
    public let headers: [(name: String, value: String)]

    /// Everything attached, with bytes.
    public let attachments: [Attachment]

    public init(
        messageID: Int64,
        text: String,
        fromHTML: Bool,
        headers: [(name: String, value: String)],
        attachments: [Attachment]
    ) {
        self.messageID = messageID
        self.text = text
        self.fromHTML = fromHTML
        self.headers = headers
        self.attachments = attachments
    }

    /// One header, case-insensitively.
    public func header(_ name: String) -> String? {
        headers.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.value
    }

    public static func == (lhs: MessageBody, rhs: MessageBody) -> Bool {
        lhs.messageID == rhs.messageID && lhs.text == rhs.text
            && lhs.fromHTML == rhs.fromHTML && lhs.attachments == rhs.attachments
            && lhs.headers.map(\.name) == rhs.headers.map(\.name)
            && lhs.headers.map(\.value) == rhs.headers.map(\.value)
    }
}

public extension MailStore {

    /// Reads a message's body off disk.
    ///
    /// - Throws: ``MailError/bodyNotLocal(id:)`` when the message is in the
    ///   index but its file is not on this Mac — an ordinary state for an IMAP
    ///   account, and one a caller should report rather than hide.
    func body(of id: Int64, includeAttachmentData: Bool = false) throws -> MessageBody {
        guard let url = Emlx.url(forMessage: id) else { throw MailError.bodyNotLocal(id: id) }
        guard let data = FileManager.default.contents(atPath: url.path) else {
            throw MailError.bodyNotLocal(id: id)
        }
        return try Self.body(ofMessage: id, emlx: data, includeAttachmentData: includeAttachmentData)
    }

    /// Parses a `.emlx` that has already been read.
    ///
    /// Separated so the parsing can be tested against fixtures rather than
    /// against somebody's mailbox.
    static func body(
        ofMessage id: Int64,
        emlx data: Data,
        includeAttachmentData: Bool = false
    ) throws -> MessageBody {
        let message = try Emlx.split(data)
        let part = MIME.parse(message)

        var text: String?
        var html: String?
        var attachments: [Attachment] = []

        /// Walks the tree, taking the first plain part and the first HTML one.
        ///
        /// First rather than last: `multipart/alternative` puts the richest
        /// version last by the RFC, but for reading in a terminal the plainest
        /// version is the one wanted, and it comes first.
        func visit(_ part: MIMEPart) {
            if part.isAttachment {
                attachments.append(Attachment(
                    messageID: id,
                    name: part.filename ?? "attachment",
                    contentType: part.contentType,
                    data: includeAttachmentData ? MIME.decode(part) : nil
                ))
                return
            }
            switch part.contentType {
            case "text/plain" where text == nil:
                text = MIME.text(of: part)
            case "text/html" where html == nil:
                html = MIME.text(of: part)
            default:
                break
            }
            part.parts.forEach(visit)
        }
        visit(part)

        let headers = part.headers.map { (name: $0.name, value: MIME.decodeWords($0.value)) }

        if let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return MessageBody(
                messageID: id, text: HTMLText.tidy(text), fromHTML: false,
                headers: headers, attachments: attachments
            )
        }
        if let html {
            return MessageBody(
                messageID: id, text: HTMLText.from(html), fromHTML: true,
                headers: headers, attachments: attachments
            )
        }
        return MessageBody(
            messageID: id, text: "", fromHTML: false, headers: headers, attachments: attachments
        )
    }
}
