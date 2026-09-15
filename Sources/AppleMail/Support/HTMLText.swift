//
//  HTMLText.swift
//  AppleMail
//
//  Created by David Sherlock on 2026.
//

import Foundation

/// Turning an HTML mail into something readable in a terminal.
///
/// Deliberately not `NSAttributedString(html:)`, which is the obvious answer
/// and the wrong one here: it renders on the main thread, it is slow enough to
/// notice over a page of results, and **it fetches remote content** — the
/// tracking pixels and remote images in a marketing email — which would turn
/// reading your own mail into telling the sender you read it.
///
/// So this is a plain scanner. It does not lay out HTML; it removes it.
enum HTMLText {

    /// Text out of HTML, with block structure kept as line breaks.
    static func from(_ html: String) -> String {
        var out = ""
        out.reserveCapacity(html.count / 2)

        var insideTag = false
        var skipping: String?          // the element whose content is dropped
        var tagName = ""
        var collectingName = false

        var index = html.startIndex
        while index < html.endIndex {
            let character = html[index]

            if character == "<" {
                insideTag = true
                collectingName = true
                tagName = ""
                index = html.index(after: index)
                continue
            }

            if insideTag {
                if character == ">" {
                    insideTag = false
                    let name = tagName.lowercased()
                    let bare = name.hasPrefix("/") ? String(name.dropFirst()) : name

                    if let skipped = skipping {
                        // Only the matching close tag ends a skipped element,
                        // so a <style> containing "<" in a selector cannot end
                        // it early.
                        if name == "/" + skipped { skipping = nil }
                    } else if ["script", "style", "head"].contains(bare), !name.hasPrefix("/") {
                        skipping = bare
                    } else if !name.hasPrefix("/"),
                              ["p", "div", "br", "tr", "li", "h1", "h2", "h3", "h4", "table"]
                                .contains(bare) {
                        // Only the OPENING tag breaks the line. Breaking on
                        // the closing one too puts a blank line between every
                        // pair of adjacent divs, which in an HTML mail — where
                        // the layout is all divs — is most of the output.
                        out.append("\n")
                    }
                    index = html.index(after: index)
                    continue
                }
                if collectingName {
                    if character.isWhitespace { collectingName = false } else { tagName.append(character) }
                }
                index = html.index(after: index)
                continue
            }

            if skipping == nil { out.append(character) }
            index = html.index(after: index)
        }

        return tidy(entities(in: out))
    }

    /// Replaces the entities that actually occur in mail.
    static func entities(in text: String) -> String {
        guard text.contains("&") else { return text }
        var out = text
        let named: [(String, String)] = [
            ("&nbsp;", " "), ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"),
            ("&quot;", "\""), ("&#39;", "'"), ("&apos;", "'"), ("&mdash;", "—"),
            ("&ndash;", "–"), ("&hellip;", "…"), ("&rsquo;", "’"), ("&lsquo;", "‘"),
            ("&ldquo;", "“"), ("&rdquo;", "”"), ("&pound;", "£"), ("&euro;", "€"),
            ("&copy;", "©"), ("&reg;", "®"), ("&trade;", "™"), ("&zwnj;", ""),
        ]
        for (entity, replacement) in named {
            out = out.replacingOccurrences(of: entity, with: replacement, options: .caseInsensitive)
        }
        return numericEntities(in: out)
    }

    /// `&#8217;` and `&#x2019;`.
    private static func numericEntities(in text: String) -> String {
        guard text.contains("&#") else { return text }
        var out = ""
        var remainder = Substring(text)

        while let start = remainder.range(of: "&#") {
            out += remainder[remainder.startIndex..<start.lowerBound]
            let rest = remainder[start.upperBound...]
            guard let end = rest.firstIndex(of: ";"),
                  rest.distance(from: rest.startIndex, to: end) <= 7
            else {
                out += "&#"
                remainder = rest
                continue
            }
            let digits = rest[rest.startIndex..<end]
            let value: UInt32?
            if digits.first == "x" || digits.first == "X" {
                value = UInt32(digits.dropFirst(), radix: 16)
            } else {
                value = UInt32(digits)
            }
            if let value, let scalar = Unicode.Scalar(value) {
                out.append(Character(scalar))
            } else {
                out += "&#" + digits + ";"
            }
            remainder = rest[rest.index(after: end)...]
        }
        return out + remainder
    }

    /// Collapses the whitespace HTML leaves behind.
    ///
    /// An HTML mail is mostly layout, so the naive strip leaves dozens of
    /// blank lines and runs of spaces from indentation. Three or more newlines
    /// become two; trailing spaces go.
    static func tidy(_ text: String) -> String {
        var lines = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                line.replacingOccurrences(of: "\u{00A0}", with: " ")
                    .replacingOccurrences(of: "[ \t]+", with: " ", options: .regularExpression)
                    .trimmingCharacters(in: .whitespaces)
            }

        var tidied: [String] = []
        var blanks = 0
        for line in lines {
            if line.isEmpty {
                blanks += 1
                if blanks > 1 { continue }
            } else {
                blanks = 0
            }
            tidied.append(line)
        }
        lines = tidied
        while lines.first?.isEmpty == true { lines.removeFirst() }
        while lines.last?.isEmpty == true { lines.removeLast() }
        return lines.joined(separator: "\n")
    }
}
