//
//  Attachment.swift
//  AppleMail
//
//  Created by David Sherlock on 2026.
//

import Foundation

/// A file that arrived with a message.
public struct Attachment: Sendable, Equatable, Codable {

    /// The message it came with.
    public let messageID: Int64

    /// The filename as the sender wrote it.
    public let name: String

    /// The MIME type, when the message file has been read.
    ///
    /// `nil` when the attachment is known only from the index, which records
    /// names and not types.
    public let contentType: String?

    /// The bytes, when they have been loaded.
    public let data: Data?

    public init(messageID: Int64, name: String, contentType: String? = nil, data: Data? = nil) {
        self.messageID = messageID
        self.name = name
        self.contentType = contentType
        self.data = data
    }

    /// The extension, lowercased, without the dot.
    public var fileExtension: String {
        (name as NSString).pathExtension.lowercased()
    }

    /// Size in bytes, when the bytes are here.
    public var size: Int? { data?.count }
}
