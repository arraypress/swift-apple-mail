# Swift Apple Mail

Read Apple Mail's message store from Swift: search, threads, bodies, and the
files people attached.

```swift
import AppleMail

let store = try MailStore()

let invoices = try store.search(MailQuery(
    subject: "invoice",
    since: Calendar.current.date(byAdding: .month, value: -6, to: .now),
    hasAttachments: true
))

for message in invoices {
    print(message.receivedAt, message.sender.described, message.displaySubject)
    try store.saveAttachments(of: message.id, to: .downloadsDirectory)
}
```

Mail keeps its index in a plain SQLite database. Reading it directly is
**4 ms across 7,000 messages**, measured on a real account — the same search
through Mail's AppleScript interface takes minutes.

## What it reads

| | |
|---|---|
| `MailStore.search(_:)` | sender, recipient, subject, mailbox, dates, flags, attachments |
| `MailStore.message(id:)` | one message |
| `MailStore.conversation(id:)` | a whole thread, oldest first |
| `MailStore.body(of:)` | the letter, decoded, from the message file |
| `MailStore.attachments(of:)` | what was attached, with bytes |
| `MailStore.saveAttachments(of:to:)` | write them out |
| `MailStore.senders(limit:since:)` | who writes to you most |
| `MailStore.mailboxes()` | every folder, with counts |
| `MailScript` | draft, flag, mark read — through Mail.app |

## Read-only, and structurally so

`MailStore` opens the index with `SQLITE_OPEN_READONLY` and no copy. There is
no code path in this library that writes to it, and there should never be one:
the schema is Apple's, undocumented, and read by a running application that
caches it.

The read-only connection sees the write-ahead log, so today's mail is there.
Copying the file first — the usual advice — misses everything still in the
`-wal`, which on a busy mailbox is everything that arrived today.

Changing anything goes through Mail itself, over AppleScript, and the surface
is deliberately narrow: compose a draft, flag a message, mark it read. It
**cannot send, delete or move**.

## Requirements

macOS 14+, and **Full Disk Access** for whatever runs it. Mail's data is in a
protected folder; without it the open fails with `SQLITE_CANTOPEN`, which is
reported as `MailError.notPermitted` rather than as a missing file.

macOS only, and not by choice — Mail's message store exists nowhere else.

## Things that cost an afternoon

Each was measured against a real account, and each is now a test.

**`"\r\n"` is one Swift `Character`.** So `split(separator: "\n")` matches
nothing in an RFC 822 message, and the first version of the header parser
returned a single header whose value was the rest of the message. It *looked*
correct, because `Content-Type` is usually the first header — the media type
came out right while every other header vanished. Headers are split on the
byte `0x0A` now. Before the fix, a real message parsed to 1 header; after, the
median is 37.

**Attachments are not in the message file.** Mail keeps them in a sibling
directory, `…/Data/<n>/Attachments/<message id>/<mime part>/<filename>`. Of
400 messages with attachments, only **32** had a local `.emlx`, while **1,626**
messages had files in that store. A library that parses the message file for
attachments finds almost none of them.

**`messages.message_id` is not the `Message-ID`.** Despite the name it is a
64-bit hash, and reading it as text hands out things like
`-9222759812030868440`. The RFC header is `message_id_header` in
`message_global_data`, joined on that same hash — and that table is checked
for at open time, because the schema has changed shape across store versions.

**Two-thirds of an IMAP mailbox has no body on this Mac.** 247 of 400 sampled
messages had a local file; the rest live on the server until something opens
them. That is an ordinary state, reported as `MailError.bodyNotLocal` rather
than as an empty body — which would read as "this message says nothing".

**Dates are plain Unix seconds**, not the 2001 epoch Core Data uses elsewhere
on this system. Verified by reading the extremes back: 2010 and today.

**The mailbox URL contains the account's email address** in its user
component. `Mailbox` drops it at parse time rather than hiding it at print
time — a value that is never stored cannot leak into a log, a payload or a bug
report.

**Not `NSAttributedString(html:)` for HTML mail.** It renders on the main
thread, it is slow, and it **fetches remote content** — the tracking pixels in
a marketing email. Reading your own mail should not tell the sender you read
it. The HTML is reduced to text by a scanner instead.

**Spotlight had 0 mail messages indexed**, so there is no fast body search to
delegate to. The index holds envelopes; bodies are files.

## Installation

```swift
.package(url: "https://github.com/arraypress/swift-apple-mail.git", from: "0.1.0")
```

## Licence

MIT.
