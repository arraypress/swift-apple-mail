//
//  SQLite.swift
//  AppleMail
//
//  Created by David Sherlock on 2026.
//
//  A read-only door onto a SQLite file. Deliberately small.
//

import Foundation
import SQLite3

/// The smallest SQLite wrapper that can run this library's queries.
///
/// Hand-rolled rather than taken as a dependency because everything here is
/// **reading somebody's live mail index**, and the whole surface worth
/// auditing is one file: it opens read-only, it binds parameters rather than
/// pasting them into SQL, and it has no code path that writes.
final class SQLiteDatabase {

    private let handle: OpaquePointer

    /// Opens a database for reading and nothing else.
    ///
    /// `SQLITE_OPEN_READONLY` on the live file, with no copy. Measured against
    /// Mail's own index: a read-only connection sees the write-ahead log, so
    /// the newest messages are there — copying the file first (the usual
    /// advice) would miss anything still in the `-wal`, which on a busy
    /// mailbox is everything that arrived today.
    init(path: String) throws {
        guard FileManager.default.fileExists(atPath: path) else {
            throw MailError.noMailData(path)
        }

        var pointer: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_URI
        // The URI form carries the mode explicitly, so a future edit cannot
        // widen the open by dropping a flag.
        let uri = "file:\(path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path)?mode=ro"
        let result = sqlite3_open_v2(uri, &pointer, flags, nil)

        guard result == SQLITE_OK, let pointer else {
            let message = pointer.map { String(cString: sqlite3_errmsg($0)) } ?? "code \(result)"
            if let pointer { sqlite3_close_v2(pointer) }
            // SQLITE_CANTOPEN on a file that plainly exists is what a TCC
            // refusal looks like from here, and "unable to open database
            // file" would send a reader to check the path they can already see.
            if result == SQLITE_CANTOPEN {
                throw MailError.notPermitted(path)
            }
            throw MailError.queryFailed(message)
        }
        handle = pointer
    }

    deinit { sqlite3_close_v2(handle) }

    /// Runs a query, handing each row to `row`.
    ///
    /// - Parameters:
    ///   - sql: The statement. Values belong in `parameters`, never here.
    ///   - parameters: Bound in order, standing in for each `?`.
    func query(_ sql: String, _ parameters: [SQLiteValue] = [], row: (Row) -> Void) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw MailError.queryFailed(String(cString: sqlite3_errmsg(handle)))
        }
        defer { sqlite3_finalize(statement) }

        for (offset, parameter) in parameters.enumerated() {
            let index = Int32(offset + 1)
            switch parameter {
            case .integer(let value):
                sqlite3_bind_int64(statement, index, value)
            case .text(let value):
                // SQLITE_TRANSIENT: SQLite copies the bytes rather than
                // holding a pointer into a Swift string that is about to go
                // out of scope.
                sqlite3_bind_text(statement, index, value, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            }
        }

        while sqlite3_step(statement) == SQLITE_ROW {
            row(Row(statement: statement))
        }
    }

    /// Whether a table exists — the index's shape has changed before.
    func hasTable(_ name: String) -> Bool {
        var found = false
        try? query(
            "select 1 from sqlite_master where type='table' and name=? limit 1",
            [.text(name)]
        ) { _ in found = true }
        return found
    }

    /// Whether a table has a column, for the same reason.
    func hasColumn(_ column: String, in table: String) -> Bool {
        var found = false
        // No parameter: PRAGMA will not take one. The caller is this library,
        // never a user, and the names are literals in source.
        try? query("pragma table_info(\(table))") { row in
            if row.text(1) == column { found = true }
        }
        return found
    }

    /// One row of a result.
    struct Row {

        let statement: OpaquePointer

        func integer(_ index: Int32) -> Int64 { sqlite3_column_int64(statement, index) }

        func text(_ index: Int32) -> String? {
            guard let bytes = sqlite3_column_text(statement, index) else { return nil }
            return String(cString: bytes)
        }

        func isNull(_ index: Int32) -> Bool {
            sqlite3_column_type(statement, index) == SQLITE_NULL
        }
    }
}

/// A value bound into a query.
enum SQLiteValue {
    case integer(Int64)
    case text(String)
}
