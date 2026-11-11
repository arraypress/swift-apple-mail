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

| Call | Reads |
|---|---|
| `MailStore.search(_:)` | sender, recipient, subject, mailbox, dates, flags, attachments |
| `MailStore.message(id:)` | one message |
| `MailStore.conversation(id:)` | a whole thread, oldest first |
| `MailStore.body(of:)` | the letter, decoded, from the message file |
| `MailStore.attachments(of:)` | what was attached, with bytes |
| `MailStore.saveAttachments(of:to:)` | write them out |
| `MailStore.senders(limit:since:)` | who writes to you most |
| `MailStore.mailboxes()` | every folder, with counts |
| `MailStore.awaitingReply(since:limit:)` | conversations where a person wrote last |
| `MailStore.filingSuggestions(in:…)` | where a mailbox's mail probably belongs, with the counts behind it |
| `MailStore.messages(messageID:)` | every copy of a message, by `Message-ID` |
| `MailStore.rawMessage(id:)` | the message as received, ready to save as `.eml` |

## What it changes — through Mail.app

| Call | Does |
|---|---|
| `MailScript.draft` | opens a filled-in draft — never sends |
| `MailScript.reply(to:all:)` / `forward(_:to:)` | opens Mail's own reply or forward — never sends |
| `MailScript.setFlag` / `setRead` | flags (in any of Mail's seven colours), unflags, marks read or unread |
| `MailScript.move` / `copy` | files messages into a mailbox |
| `MailScript.createMailbox` / `renameMailbox` | makes and renames mailboxes |
| `MailScript.rules` / `addFilingRule` | lists Mail's rules; adds one that only files |
| `MailScript.checkForNewMail` | asks Mail to fetch |

Messages are named by `MessageLocator` — mailbox plus `Message-ID` — not by
index id, because the id changes when a message moves.

## Read-only, and structurally so

`MailStore` opens the index with `SQLITE_OPEN_READONLY` and no copy, through
[swift-sqlite-reader](https://github.com/arraypress/swift-sqlite-reader)'s
`.readOnly`. There is
no code path in this library that writes to it, and there should never be one:
the schema is Apple's, undocumented, and read by a running application that
caches it.

The read-only connection sees the write-ahead log, so today's mail is there.
Copying the file first — the usual advice — misses everything still in the
`-wal`, which on a busy mailbox is everything that arrived today.

Changing anything goes through Mail itself, over AppleScript, and only for
things that can be undone. It **cannot send mail, delete a message or remove a
mailbox**, and `MailboxSafety` refuses Trash, Junk, Drafts, Sent and Outbox as
a destination for `move`, `copy` or a rule — the mailboxes Mail empties or
sends from. A batch finds every message and the destination before it changes
anything; if one is missing, nothing changes. A rule is made switched off,
read back and checked, and only then switched on.

**You pass the thing that runs AppleScript** (0.2.0). Every `MailScript` call
takes `using runner: AppleScriptRunner` — `(source, arguments) throws -> String`
— and the library no longer starts osascript itself. In the fleet that runner is
CLIKit's `OSAScript.run`, which has a hard timeout, reads stdout and stderr
together, and says whether a failure may already have acted:

```swift
try MailScript.draft(to: ["ada@example.com"], subject: "Hi", body: "…",
                     using: { try OSAScript.run($0, arguments: $1) })
```

The scripts are constants; every value — subject, body, addresses, the
Message-ID — reaches them as `argv`, never pasted into the source.

## Requirements

macOS 14+, and **Full Disk Access** for whatever runs it. Mail's data is in a
protected folder; without it macOS refuses the read (SQLite alone would say
only `SQLITE_CANTOPEN`), which is reported as `MailError.notPermitted` rather
than as a missing file.

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

**Mail's `message id` has no angle brackets; the index's does.** Asking Mail
for `<…>` matches nothing, so `mark` in 0.1 and 0.2 reported every message as
not found. `MessageIDs.bare` strips them now.

**A `Message-ID` is not unique once there are copies.** `copy` gives two
messages the same one, so a locator could name the original when the copy was
meant. The locator carries the mailbox, and `messages(messageID:)` returns
every match so a caller can refuse an ambiguous one.

**The index percent-encodes mailbox names, with accents decomposed** —
`Sent%20Messages`, `Hotel%20(Zu%CC%88rich)`. A mailbox filter written as Mail
shows the name matched nothing for anything with a space or an accent. All
three spellings are tried now.

**AppleScript variables can collide with Mail's dictionary at run time**, not
compile time: a variable called `base` compiles and then fails inside a
`tell application "Mail"` block. Every variable in the scripts is `v`-prefixed.

**On iCloud, a nested mailbox made in one go has a hollow parent.** Asking
for `A/B` when `A` did not exist made `A` as a container only (IMAP's
`\Noselect`; an iPhone shows it greyed out). Mail on the Mac showed it as an
ordinary mailbox and reported a move into it as done — and two minutes later
the server put the message back where it came from. `createMailbox` makes
each level on its own now (0.3.1), and a message moved into a level made that
way stays. A hollow folder made before then stays hollow: make it again in
Mail, or file into a folder below it.

**What Mail's scripting will not do**, measured on macOS 27: `delete` on a
mailbox fails with -10000 even when it is empty, so there is no way to remove
one; setting `content` on a reply reads back empty, so a reply has no body;
and Mail's index can take over a minute to list a mailbox Mail itself can
already use.

**Spotlight had 0 mail messages indexed**, so there is no fast body search to
delegate to. The index holds envelopes; bodies are files.

## Installation

```swift
.package(url: "https://github.com/arraypress/swift-apple-mail.git", from: "0.3.1")
```

## Licence

MIT.
