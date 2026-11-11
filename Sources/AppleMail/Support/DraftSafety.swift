//
//  DraftSafety.swift
//  AppleMail
//
//  Created by David Sherlock on 2026.
//
//  Which files may be attached to a draft.
//

import Foundation

/// The checks a file passes before it is attached to a draft.
public enum DraftSafety {

    /// Why a file cannot be attached, or `nil` when it can.
    ///
    /// It must be an existing, readable, ordinary file — not a folder — and
    /// it must not sit in a hidden folder or be hidden itself. Keys, tokens
    /// and credentials live in places like `~/.ssh` and `~/.config`; a draft
    /// is not sent, but mail read by an agent can ask it to attach things, and
    /// a person glancing at a draft before pressing Send may not notice one.
    public static func attachmentProblem(_ file: URL) -> String? {
        guard file.isFileURL else { return "\(file.absoluteString) is not a file on this Mac" }
        let resolved = file.standardizedFileURL.resolvingSymlinksInPath()
        if let hidden = resolved.pathComponents.first(where: { $0.hasPrefix(".") && $0 != "." && $0 != ".." }) {
            return "\(file.path) is inside a hidden folder or is hidden (\(hidden)) — not attached"
        }
        var isFolder: ObjCBool = false
        guard FileManager.default.fileExists(atPath: resolved.path, isDirectory: &isFolder) else {
            return "no file at \(file.path)"
        }
        if isFolder.boolValue { return "\(file.path) is a folder — attach the files in it, or zip it first" }
        guard FileManager.default.isReadableFile(atPath: resolved.path) else {
            return "\(file.path) cannot be read"
        }
        return nil
    }
}
