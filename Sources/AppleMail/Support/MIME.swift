//
//  MIME.swift
//  AppleMail
//
//  Created by David Sherlock on 2026.
//
//  Enough of RFC 2045/2047 to read a letter and pull its attachments out.
//

import Foundation

/// A parsed MIME message.
struct MIMEPart {

    var headers: [(name: String, value: String)] = []
    var body: Data = Data()
    var parts: [MIMEPart] = []

    /// The first value of a header, case-insensitively.
    func header(_ name: String) -> String? {
        headers.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.value
    }

    /// The media type, lowercased, without its parameters.
    var contentType: String {
        (header("Content-Type") ?? "text/plain")
            .split(separator: ";").first
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() } ?? "text/plain"
    }

    /// A parameter of a header, e.g. the `boundary` of a Content-Type.
    func parameter(_ name: String, of headerName: String) -> String? {
        guard let value = header(headerName) else { return nil }
        for piece in value.split(separator: ";").dropFirst() {
            let trimmed = piece.trimmingCharacters(in: .whitespaces)
            guard let equals = trimmed.firstIndex(of: "=") else { continue }
            let key = trimmed[trimmed.startIndex..<equals].trimmingCharacters(in: .whitespaces)
            guard key.caseInsensitiveCompare(name) == .orderedSame else { continue }
            var found = String(trimmed[trimmed.index(after: equals)...])
                .trimmingCharacters(in: .whitespaces)
            if found.hasPrefix("\""), found.hasSuffix("\""), found.count >= 2 {
                found = String(found.dropFirst().dropLast())
            }
            return found
        }
        return nil
    }

    /// The filename this part would be saved under, if it is a file.
    var filename: String? {
        if let name = parameter("filename", of: "Content-Disposition") { return decoded(name) }
        if let name = parameter("name", of: "Content-Type") { return decoded(name) }
        return nil
    }

    /// Whether this part is a file rather than the letter.
    ///
    /// An inline image in a signature is an attachment by MIME's reckoning and
    /// not by anybody else's, so having a filename is the test rather than the
    /// disposition — `inline` parts with names are the signature logos, and
    /// they are still files somebody may want.
    var isAttachment: Bool {
        filename != nil && !contentType.hasPrefix("multipart/")
    }

    private func decoded(_ value: String) -> String {
        MIME.decodeWords(value)
    }
}

/// Parsing and decoding MIME.
enum MIME {

    // MARK: - Parsing

    /// Parses a message into headers, a body, and any nested parts.
    static func parse(_ data: Data) -> MIMEPart {
        var part = MIMEPart()

        let (headerData, bodyData) = splitHeaders(data)
        part.headers = parseHeaders(headerData)
        part.body = bodyData

        guard part.contentType.hasPrefix("multipart/"),
              let boundary = part.parameter("boundary", of: "Content-Type"),
              !boundary.isEmpty
        else {
            return part
        }
        part.parts = split(bodyData, boundary: boundary).map(parse)
        return part
    }

    /// Splits a message at the blank line between headers and body.
    ///
    /// Handles both line endings. Mail stores CRLF as it arrived, but a
    /// message that has been through a gateway may be LF-only, and a parser
    /// that only knows one of them reads the entire letter as headers.
    private static func splitHeaders(_ data: Data) -> (Data, Data) {
        let crlfcrlf = Data([0x0D, 0x0A, 0x0D, 0x0A])
        let lflf = Data([0x0A, 0x0A])

        if let range = data.firstRange(of: crlfcrlf) {
            return (data[data.startIndex..<range.lowerBound], data[range.upperBound...])
        }
        if let range = data.firstRange(of: lflf) {
            return (data[data.startIndex..<range.lowerBound], data[range.upperBound...])
        }
        return (data, Data())
    }

    /// Reads header lines, joining folded continuations.
    ///
    /// Split on the **byte** `0x0A`, not on the Character `"\n"`. In Swift a
    /// CRLF is a single grapheme cluster, so `split(separator: "\n")` matches
    /// nothing at all in a CRLF document — which every RFC 822 message is.
    /// The first version of this did exactly that: it returned one header
    /// whose value was the rest of the message, and it looked like it worked
    /// because `Content-Type` is usually the first header, so the media type
    /// still came out right while every other header vanished.
    static func parseHeaders(_ data: Data) -> [(name: String, value: String)] {
        var headers: [(String, String)] = []
        var current: (name: String, value: String)?

        for rawLine in data.split(separator: 0x0A, omittingEmptySubsequences: false) {
            let bytes = rawLine.last == 0x0D ? rawLine.dropLast() : rawLine
            let line = String(decoding: bytes, as: UTF8.self)

            // A line starting with space or tab continues the one before it.
            // Long Subject and To headers are folded this way as a matter of
            // course, and treating a continuation as a new header loses the
            // rest of the value.
            if let first = line.first, first == " " || first == "\t" {
                current?.value += " " + line.trimmingCharacters(in: .whitespaces)
                continue
            }
            if let finished = current { headers.append(finished) }
            current = nil

            guard let colon = line.firstIndex(of: ":") else { continue }
            current = (
                String(line[line.startIndex..<colon]),
                String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            )
        }
        if let finished = current { headers.append(finished) }
        return headers.map { (name: $0.0, value: $0.1) }
    }

    /// Splits a multipart body on its boundary.
    private static func split(_ data: Data, boundary: String) -> [Data] {
        let marker = Data("--\(boundary)".utf8)
        var parts: [Data] = []
        var searchFrom = data.startIndex
        var partStart: Data.Index?

        while let range = data[searchFrom...].firstRange(of: marker) {
            if let start = partStart {
                var end = range.lowerBound
                // Drop the CRLF that belongs to the boundary, not the part.
                if end > start, data[data.index(before: end)] == 0x0A { end = data.index(before: end) }
                if end > start, data[data.index(before: end)] == 0x0D { end = data.index(before: end) }
                parts.append(data[start..<end])
            }
            // `--boundary--` ends the multipart; anything after is epilogue.
            let afterMarker = range.upperBound
            let isClosing = data.count >= data.distance(from: data.startIndex, to: afterMarker) + 2
                && data[afterMarker] == 0x2D
                && data[data.index(after: afterMarker)] == 0x2D
            if isClosing { break }

            var next = afterMarker
            if next < data.endIndex, data[next] == 0x0D { next = data.index(after: next) }
            if next < data.endIndex, data[next] == 0x0A { next = data.index(after: next) }
            partStart = next
            searchFrom = next
            if searchFrom >= data.endIndex { break }
        }
        return parts
    }

    // MARK: - Decoding

    /// Decodes a part's body according to its transfer encoding.
    static func decode(_ part: MIMEPart) -> Data {
        switch (part.header("Content-Transfer-Encoding") ?? "").lowercased()
            .trimmingCharacters(in: .whitespaces) {
        case "base64":
            let text = String(decoding: part.body, as: UTF8.self)
                .components(separatedBy: .whitespacesAndNewlines).joined()
            return Data(base64Encoded: text, options: [.ignoreUnknownCharacters]) ?? part.body
        case "quoted-printable":
            return quotedPrintable(part.body)
        default:
            return part.body
        }
    }

    /// Decodes quoted-printable, including soft line breaks.
    static func quotedPrintable(_ data: Data) -> Data {
        var out = Data()
        out.reserveCapacity(data.count)
        var index = data.startIndex

        while index < data.endIndex {
            let byte = data[index]
            guard byte == 0x3D else {  // "="
                out.append(byte)
                index = data.index(after: index)
                continue
            }

            let first = data.index(after: index)
            guard first < data.endIndex else { break }

            // "=\r\n" or "=\n" is a soft break: the line continues, and
            // nothing is emitted.
            if data[first] == 0x0D || data[first] == 0x0A {
                var next = first
                if data[next] == 0x0D { next = data.index(after: next) }
                if next < data.endIndex, data[next] == 0x0A { next = data.index(after: next) }
                index = next
                continue
            }

            let second = data.index(after: first)
            guard second < data.endIndex,
                  let value = UInt8(
                    String(decoding: [data[first], data[second]], as: UTF8.self), radix: 16
                  )
            else {
                out.append(byte)
                index = data.index(after: index)
                continue
            }
            out.append(value)
            index = data.index(after: second)
        }
        return out
    }

    /// Decodes RFC 2047 encoded words — `=?UTF-8?Q?Ren=C3=A9?=`.
    ///
    /// Subject lines and display names arrive this way whenever they leave
    /// ASCII, which for real mail is constantly. Without this, a name comes
    /// out as the encoding rather than the name.
    static func decodeWords(_ value: String) -> String {
        guard value.contains("=?") else { return value }

        var result = ""
        var remainder = Substring(value)

        while let start = remainder.range(of: "=?") {
            result += remainder[remainder.startIndex..<start.lowerBound]
            let afterStart = remainder[start.upperBound...]

            guard let end = afterStart.range(of: "?=") else {
                result += remainder[start.lowerBound...]
                return result
            }

            let word = afterStart[afterStart.startIndex..<end.lowerBound]
            let pieces = word.split(separator: "?", maxSplits: 2, omittingEmptySubsequences: false)

            if pieces.count == 3, let decoded = decodeWord(
                charset: String(pieces[0]), transfer: String(pieces[1]), text: String(pieces[2])
            ) {
                result += decoded
            } else {
                result += "=?" + word + "?="
            }
            remainder = afterStart[end.upperBound...]
        }
        result += remainder
        return result
    }

    /// One encoded word.
    private static func decodeWord(charset: String, transfer: String, text: String) -> String? {
        let bytes: Data?
        switch transfer.uppercased() {
        case "B":
            bytes = Data(base64Encoded: text, options: [.ignoreUnknownCharacters])
        case "Q":
            // In an encoded word, "_" means a space. Everything else is
            // quoted-printable.
            bytes = quotedPrintable(Data(text.replacingOccurrences(of: "_", with: " ").utf8))
        default:
            return nil
        }
        guard let bytes else { return nil }
        return String(data: bytes, encoding: encoding(named: charset)) ?? String(decoding: bytes, as: UTF8.self)
    }

    /// Maps a charset name onto a `String.Encoding`.
    static func encoding(named charset: String) -> String.Encoding {
        let name = charset.trimmingCharacters(in: .whitespaces).lowercased()
        switch name {
        case "utf-8", "utf8": return .utf8
        case "us-ascii", "ascii": return .ascii
        case "iso-8859-1", "latin1": return .isoLatin1
        case "iso-8859-2": return .isoLatin2
        case "windows-1252", "cp1252": return .windowsCP1252
        case "utf-16": return .utf16
        default:
            // CoreFoundation knows hundreds more, including every GB and Shift
            // JIS variant. Falling back to UTF-8 would turn a Japanese mail
            // into replacement characters.
            let cf = CFStringConvertIANACharSetNameToEncoding(name as CFString)
            guard cf != kCFStringEncodingInvalidId else { return .utf8 }
            return String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cf))
        }
    }

    /// Text out of a part, decoded and read in its own charset.
    static func text(of part: MIMEPart) -> String {
        let bytes = decode(part)
        let charset = part.parameter("charset", of: "Content-Type") ?? "utf-8"
        return String(data: bytes, encoding: encoding(named: charset))
            ?? String(decoding: bytes, as: UTF8.self)
    }
}
