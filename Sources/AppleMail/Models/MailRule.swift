//
//  MailRule.swift
//  AppleMail
//
//  Created by David Sherlock on 2026.
//

import Foundation

/// One of Mail's rules, as Mail reports it.
public struct MailRule: Sendable, Equatable, Codable {

    public let name: String
    public let enabled: Bool

    /// Whether every condition must hold (`true`) or any one (`false`).
    public let matchesAll: Bool

    /// Each condition as Mail words it: `from header does contain value x`.
    public let conditions: [String]

    /// Each thing the rule does: `move to Receipts/Shop`, `delete`,
    /// `forward to x`. Every action Mail reports is listed — including the
    /// ones this library will never create — so a listing shows what a rule
    /// really does.
    public let actions: [String]

    public init(name: String, enabled: Bool, matchesAll: Bool, conditions: [String], actions: [String]) {
        self.name = name
        self.enabled = enabled
        self.matchesAll = matchesAll
        self.conditions = conditions
        self.actions = actions
    }
}

/// What a filing rule matches on.
public enum RuleField: String, Sendable, Equatable, Codable, CaseIterable {
    /// The `From` header.
    case from
    /// The `Subject` header.
    case subject
    /// The `To` header.
    case to

    /// Mail's `rule type` constant. One of three fixed words — never a value.
    var appleScriptType: String {
        switch self {
        case .from: "from header"
        case .subject: "subject header"
        case .to: "to header"
        }
    }
}
