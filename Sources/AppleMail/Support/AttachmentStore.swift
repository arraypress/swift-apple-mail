//
//  AttachmentStore.swift
//  AppleMail
//
//  Created by David Sherlock on 2026.
//
//  Where the attached files actually are.
//

import Foundation
import UniformTypeIdentifiers

/// Mail's separate store of attached files.
///
/// Attachments are **not** kept inside the message file, and assuming they are
/// is the mistake that makes an extraction tool look broken: measured on a
/// real account, only 32 of 400 messages that have attachments had a local
/// `.emlx` at all, while 1,626 messages had files sitting in this store.
///
/// The layout is a sibling of the `Messages` directory:
///
/// ```
/// …/Data/7/Attachments/<message id>/<mime part>/<filename>
/// ```
///
/// The middle component is the message's row identifier — verified against a
/// live index, 200 of 200 sampled directory names were real identifiers, and
/// 59 of 60 carried a filename the index also recorded.
public enum AttachmentStore {

    /// Every attached file on this Mac, keyed by message identifier.
    public static func index(root: URL? = nil) -> [Int64: [URL]] {
        let base = root ?? Emlx.defaultRoot()
        if let cached = cache.value(for: base) { return cached }

        var found: [Int64: [URL]] = [:]
        if let walker = FileManager.default.enumerator(
            at: base, includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) {
            while let url = walker.nextObject() as? URL {
                // …/Attachments/<id>/<part>/<file> — so the grandparent's
                // parent is the marker, and the grandparent is the id.
                let partDirectory = url.deletingLastPathComponent()
                let messageDirectory = partDirectory.deletingLastPathComponent()
                guard messageDirectory.deletingLastPathComponent().lastPathComponent == "Attachments",
                      let id = Int64(messageDirectory.lastPathComponent)
                else { continue }
                found[id, default: []].append(url)
            }
        }
        cache.store(found, for: base)
        return found
    }

    /// Forgets the walked list.
    public static func forgetIndex() { cache.clear() }

    /// The files attached to one message, from this store alone.
    public static func attachments(
        of id: Int64,
        includeData: Bool = false,
        root: URL? = nil
    ) -> [Attachment] {
        (index(root: root)[id] ?? [])
            .sorted { $0.path < $1.path }
            .map { url in
                Attachment(
                    messageID: id,
                    name: url.lastPathComponent,
                    contentType: contentType(of: url),
                    data: includeData ? FileManager.default.contents(atPath: url.path) : nil
                )
            }
    }

    /// The media type for a file, from its extension.
    ///
    /// The store keeps no type alongside the bytes — unlike the message file,
    /// where MIME states it — so this is inferred. A caller writing the file
    /// back out gets the extension it arrived with either way.
    static func contentType(of url: URL) -> String? {
        UTType(filenameExtension: url.pathExtension)?.preferredMIMEType
    }
}

/// Remembers one walk of the attachment tree.
private final class WalkCache: @unchecked Sendable {

    private var storage: [URL: [Int64: [URL]]] = [:]
    private let lock = NSLock()

    func value(for root: URL) -> [Int64: [URL]]? {
        lock.lock(); defer { lock.unlock() }
        return storage[root]
    }

    func store(_ value: [Int64: [URL]], for root: URL) {
        lock.lock(); defer { lock.unlock() }
        storage[root] = value
    }

    func clear() {
        lock.lock(); defer { lock.unlock() }
        storage.removeAll()
    }
}

private let cache = WalkCache()

public extension MailStore {

    /// Everything attached to a message, wherever it is kept.
    ///
    /// Looks in Mail's attachment store first, because that is where the files
    /// nearly always are, and falls back to the MIME parts of the message file
    /// for anything the store does not hold. Duplicates are matched on
    /// filename and the copy with bytes wins.
    ///
    /// - Parameter includeData: Whether to load the bytes. Off by default —
    ///   this account holds 477 MB of attachments, and a listing should not
    ///   read them.
    func attachments(of id: Int64, includeData: Bool = false) throws -> [Attachment] {
        var found = AttachmentStore.attachments(of: id, includeData: includeData)
        var names = Set(found.map(\.name))

        // The message file, when there is one, may carry parts the store does
        // not — an inline image, or an attachment on a message Mail has fully
        // downloaded but not split out.
        if let body = try? body(of: id, includeAttachmentData: includeData) {
            for attachment in body.attachments where !names.contains(attachment.name) {
                found.append(attachment)
                names.insert(attachment.name)
            }
        }

        // Last resort: the index knows the names even when no bytes are here,
        // so a caller asking "what was attached" gets an answer for a message
        // that was never downloaded.
        if found.isEmpty {
            found = try attachmentNames(messageID: id).map {
                Attachment(messageID: id, name: $0)
            }
        }
        return found
    }

    /// Writes a message's attachments into a directory.
    ///
    /// - Returns: The files written.
    /// - Note: An existing file is never overwritten; a number is added to the
    ///   name instead. Two messages routinely attach `invoice.pdf`.
    @discardableResult
    func saveAttachments(of id: Int64, to directory: URL) throws -> [URL] {
        let manager = FileManager.default
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)

        var written: [URL] = []
        for attachment in try attachments(of: id, includeData: true) {
            guard let data = attachment.data else { continue }
            var destination = directory.appendingPathComponent(attachment.name)
            var counter = 2
            while manager.fileExists(atPath: destination.path) {
                let base = (attachment.name as NSString).deletingPathExtension
                let ext = (attachment.name as NSString).pathExtension
                let name = ext.isEmpty ? "\(base) \(counter)" : "\(base) \(counter).\(ext)"
                destination = directory.appendingPathComponent(name)
                counter += 1
            }
            try data.write(to: destination, options: .atomic)
            written.append(destination)
        }
        return written
    }
}
