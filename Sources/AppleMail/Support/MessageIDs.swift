//
//  MessageIDs.swift
//  AppleMail
//
//  Created by David Sherlock on 2026.
//

import Foundation

/// The two spellings of a `Message-ID`, and the one Mail's scripting wants.
enum MessageIDs {

    /// `<abc@host>` → `abc@host`.
    ///
    /// The index stores the header as written, angle brackets and all; Mail's
    /// `message id` property holds it without them. Asking Mail for the
    /// bracketed form matches nothing — which is why `mark` never found a
    /// message before 0.3.0.
    static func bare(_ id: String) -> String {
        var trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("<"), trimmed.hasSuffix(">"), trimmed.count >= 2 {
            trimmed = String(trimmed.dropFirst().dropLast())
        }
        return trimmed
    }

    /// Whether this can be handed to Mail as an identifier: something with an
    /// `@`, on one line, with no double quote. It travels in `argv` either
    /// way; the check is that it looks like what it claims to be.
    static func isUsable(_ id: String) -> Bool {
        let bare = bare(id)
        return !bare.isEmpty && bare.contains("@") && !bare.contains("\"")
            && !bare.contains(where: \.isNewline)
    }
}
