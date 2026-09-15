//
//  Emlx.swift
//  AppleMail
//
//  Created by David Sherlock on 2026.
//
//  Finding, and reading, the file a message is kept in.
//

import Foundation

/// Where Mail keeps message files, and what shape they are.
///
/// A `.emlx` is three things stacked: a line holding the byte count, then the
/// message exactly as RFC 822 has it, then a property list of Mail's own
/// bookkeeping. Only the middle part is mail.
///
/// **Not every message has one.** An IMAP account keeps the envelope in the
/// index and leaves the body on the server until something opens it — measured
/// on a real account, 39 of 60 sampled messages had a local file. That is an
/// ordinary state, and the library reports it as ``MailError/bodyNotLocal``
/// rather than as an empty body, which would read as "this message says
/// nothing".
public enum Emlx {

    /// The message file for a row identifier, if it is on this Mac.
    ///
    /// The filename is the row identifier — verified against a live index —
    /// but the directory is not derivable: it depends on the account UUID, the
    /// mailbox UUID and a shard number Mail chooses. So the tree is walked
    /// once and remembered. Measured: 4,799 files in 0.11 s, which is cheaper
    /// than one `find` per message.
    public static func url(forMessage id: Int64, in root: URL? = nil) -> URL? {
        index(root: root)[String(id)]
    }

    /// Every message file on this Mac, keyed by row identifier.
    public static func index(root: URL? = nil) -> [String: URL] {
        let base = root ?? defaultRoot()
        if let cached = cache.value(for: base) { return cached }

        var found: [String: URL] = [:]
        let keys: [URLResourceKey] = [.isRegularFileKey]
        if let walker = FileManager.default.enumerator(
            at: base, includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) {
            while let url = walker.nextObject() as? URL {
                guard url.pathExtension == "emlx" else { continue }
                // `.partial.emlx` is a message Mail has only the start of —
                // headers, no body. Taking one as the message would show a
                // truncated letter as if it were whole.
                let name = url.deletingPathExtension().lastPathComponent
                guard !name.hasSuffix(".partial") else { continue }
                found[name] = url
            }
        }
        cache.store(found, for: base)
        return found
    }

    /// Forgets the walked file list — for a long-running process that wants to
    /// see mail which arrived after it started.
    public static func forgetIndex() { cache.clear() }

    /// Mail's data directory.
    static func defaultRoot() -> URL {
        let root = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mail", isDirectory: true)
        let versions = ((try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? [])
            .compactMap { name -> (Int, String)? in
                guard name.hasPrefix("V"), let number = Int(name.dropFirst()) else { return nil }
                return (number, name)
            }
            .sorted { $0.0 > $1.0 }
        guard let newest = versions.first?.1 else { return root }
        return root.appendingPathComponent(newest, isDirectory: true)
    }

    /// Splits a `.emlx` into the RFC 822 message and Mail's trailing plist.
    ///
    /// The first line is a byte count, and it is **authoritative**: the plist
    /// that follows contains angle brackets and colons of its own, so looking
    /// for "where the message ends" by scanning is how bookkeeping ends up
    /// rendered as the last paragraph of somebody's email.
    public static func split(_ data: Data) throws -> Data {
        guard let newline = data.firstIndex(of: 0x0A) else {
            throw MailError.malformedMessage("no length line")
        }
        let header = String(decoding: data[data.startIndex..<newline], as: UTF8.self)
        guard let length = Int(header.trimmingCharacters(in: .whitespaces)) else {
            throw MailError.malformedMessage("length line is not a number")
        }

        let start = data.index(after: newline)
        let end = data.index(start, offsetBy: length, limitedBy: data.endIndex) ?? data.endIndex
        return data[start..<end]
    }
}

/// Remembers one walk of the message tree.
///
/// A class rather than a static dictionary so the mutation is behind a lock:
/// two callers reading mail at once is an ordinary thing for a library to have
/// to survive.
private final class WalkCache: @unchecked Sendable {

    private var storage: [URL: [String: URL]] = [:]
    private let lock = NSLock()

    func value(for root: URL) -> [String: URL]? {
        lock.lock(); defer { lock.unlock() }
        return storage[root]
    }

    func store(_ value: [String: URL], for root: URL) {
        lock.lock(); defer { lock.unlock() }
        storage[root] = value
    }

    func clear() {
        lock.lock(); defer { lock.unlock() }
        storage.removeAll()
    }
}

private let cache = WalkCache()
