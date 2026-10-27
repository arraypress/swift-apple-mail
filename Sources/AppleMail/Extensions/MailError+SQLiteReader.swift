//
//  MailError+SQLiteReader.swift
//  AppleMail
//
//  Created by David Sherlock on 2026.
//
//  The index is read through swift-sqlite-reader; its errors are reported
//  as this library's own, so callers and messages stay the same.
//

import Foundation
import SQLiteReader

extension MailError {

    /// This library's error for a reader's.
    init(_ error: SQLiteReaderError) {
        switch error {
        case .notFound(let path): self = .noMailData(path)
        case .permissionDenied(let path): self = .notPermitted(path)
        case .unreadable(_, let reason): self = .queryFailed(reason)
        }
    }
}
