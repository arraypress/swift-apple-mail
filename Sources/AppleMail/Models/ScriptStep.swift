//
//  ScriptStep.swift
//  AppleMail
//
//  Created by David Sherlock on 2026.
//

import Foundation

/// What happened to one message in a batch Mail was asked to change.
///
/// A batch either refuses before touching anything (``MailError/scriptFailed(_:)``
/// naming what was missing) or works through the messages in order and stops
/// at the first failure. So every message ends in one of three states, and a
/// caller can tell "done" from "never tried" from "tried and Mail objected".
public enum ScriptStep: Sendable, Equatable {
    /// Mail did it.
    case done
    /// Mail was asked and refused, with its words.
    case failed(String)
    /// An earlier message failed, so this one was never attempted.
    case notAttempted
}
