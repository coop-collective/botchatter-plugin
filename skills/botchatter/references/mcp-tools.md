# BotChatter MCP tools

Server: `botchatter`, streamable HTTP at `<host>/mcp` (default `https://staging.botchatter.ai/mcp`),
protected by OAuth 2.1 (PKCE S256, dynamic client registration at `/oauth/register`, Client ID
Metadata Documents). Scope: `telegram` (it covers both providers). An unauthenticated request
answers 401 with a `WWW-Authenticate` challenge pointing to `/.well-known/oauth-protected-resource/mcp`.

Every tool returns one text item holding JSON (`get_media` adds an image or a file), or an error
(`isError: true`) whose text is a readable message. All tools count toward **30 calls a minute
per account**. `provider` is `"telegram"` or `"whatsapp"`; where it is optional, results merge both
connected providers, newest first, each item carrying its `provider`.

Common shapes: a **chat** is `{provider, chat_ref, chat_key, title, type, unread_count,
last_message_at}` (`type`: `private`, `group`, `channel`, `bot`, `saved_messages`;
`unread_count` is null on WhatsApp). A **message** is `{id, from, date, text}` plus, when they
apply, `reply_to_id`, `forwarded`, `edited`, `mentions_me` and `media` (`{type, mimetype,
fileName, size}`). `id` is a number on Telegram, a string on WhatsApp. `chat_ref` starts with
`cr1.` (Telegram) or `wr1.` (WhatsApp); pass it back unchanged.

Chats the user has hidden never appear in lists or search results; opening one by `chat_ref`
fails with the hidden-chat error below.

## Accounts

### connection_status()

```json
{ "telegram": { "state": "connected", "account": { "name": "Ana B.", "username": "anab" } },
  "whatsapp": { "state": "locked", "account": { "name": "Ana", "phone": "+44 •••• ••12" }, "messages_synced": 812 } }
```

Telegram `state`: `connected`, `not_connected` or `revoked` (reconnect). WhatsApp `state` (beta):
`not_connected`, `connecting`, `connected`, `locked` (paired; reconnects on the next read) or
`revoked` (the linked device was removed; reconnect). Also reports WhatsApp history import progress.

### connect_account({ provider = "telegram" })

```json
{ "provider": "telegram", "connect_url": "https://…/link/cl2.…", "expires_in_seconds": 1800 }
```

A 30-minute link for the account's own human only. It carries a 2-hour device unlock for the
account's encrypted data, so treat it as a secret: never post it publicly or anywhere but the
private conversation with that person. Opening it gives a connect-only session.

- Telegram: scan the QR code in Telegram under Settings → Devices → Link Desktop Device, or tap
  the `tg://` link on the phone that has Telegram.
- WhatsApp (beta, not yet tested against a real account): the link opens `/connect/whatsapp`;
  scan the QR code in WhatsApp under Settings → Linked devices → Link a device. The QR code must
  be on a computer or another screen, not on the phone that scans it.

## Catching up

### catch_up({ provider?, since?, max_chats: 1..20 = 10, per_chat: 1..10 = 5 })

The one call for "what's new": chats with activity since the last `catch_up` (or `since`, an ISO
date-time; the first time, the last 24 hours), newest first, each `{provider, chat, messages}`.
Each call moves the "last catch_up" mark forward, so to look at the same window again pass
`since`. Prefer it over `list_recent_chats` plus `read_recent_messages` per chat. WhatsApp only
knows messages captured while connected.

### get_mentions({ provider?, limit: 1..30 = 15 })

Messages that @mention the user or reply to the user's messages, across chats and groups:
usually what needs an answer. Each item is `{chat, message}`.

## Chats and people

### list_recent_chats({ limit: 1..20 = 10, provider? })

The most recent chats, newest first. Telegram archived chats are excluded. For an older chat by
name, use `find_chats`.

### find_chats({ query = "", type?, provider?, limit: 1..20 = 10 })

Any chat or group by name (not only recent ones), for example "Mum" or "Barcelona trip". An
empty `query` with a `type` lists chats of that type.

### get_chat_info({ chat_ref, member_limit: 1..100 = 50 })

Details of one chat: for a group its description, member count and members (names, admin flag);
for a private chat, the other person.

### find_contacts({ query, provider?, limit: 1..50 = 20 })

People by name, username or number: `{name, username, phone_masked, chat_ref?}`. Phone numbers
are masked; only a single exact name or username match includes the full `phone`. Results
include the 1:1 `chat_ref` when one exists.

## Messages

### read_recent_messages({ chat_ref, limit: 1..30 = 20, before? })

```json
{ "provider": "whatsapp",
  "messages": [{ "id": "3EB0…", "from": "Ana", "date": "2026-10-14T18:03:00Z", "text": "See you at 7?" }],
  "sync": { "state": "partial", "oldest_synced": "2026-10-12T09:00:00Z", "note": "…" } }
```

Newest first. Never marks anything as read. To page back, pass `before` = the `date` of the
oldest message you have (on WhatsApp this may ask the phone for older history). Telegram has no
`sync`. On WhatsApp `sync.state: "partial"` means older messages may be missing: say so instead
of claiming there are none.

### get_message_context({ chat_ref, message_id, before: 0..15 = 5, after: 0..15 = 5 })

The conversation around one message (for example a search hit), oldest first, including the
message itself.

### search_messages({ query, provider?, chat_ref?, limit: 1..20 = 10, type = "any" })

Search all chats, or one `chat_ref`. Every word must match (case-insensitive); quote a phrase to
keep it together; try a few phrasings for fuzzy needs. `type` (`text`, `photo`, `video`,
`document`, `audio`, `any`) finds WhatsApp media by caption or file name. Returns `{results,
whatsapp?: {sync}}`: WhatsApp searches only captured messages.

### get_media({ chat_ref, message_id })

Downloads one photo, video, voice note or document from a message (up to 5 MB) so you can look
at it; nothing is stored. Returns `{mimetype, file_name, size}` plus an image, or a file
resource. Ask before opening media unrelated to the user's request.

## Replies (sent only after the user approves each one)

### request_reply_approval({ chat_ref, text: 1..4000 chars })

The assistant app shows the user an approval form in the chat (MCP form elicitation; the app
renders it and the model cannot answer it). The form shows the provider, chat and exact text;
the user may edit the text, then approves or declines. Approval sends it once, exactly as
approved, and the call returns:

```json
{ "approval_id": "…", "state": "sent", "text": "final text, as approved", "approval_url": "https://…/approvals/…" }
```

Other results: `state: "failed"` with `error` and `ambiguous` (as below); `state: "rejected"`
when the user declines (nothing sent); `state: "pending"` with a `note` when the user has not
answered within about 2 minutes. A late answer still applies; unanswered requests expire after
15 minutes and are never sent (state `withdrawn`). `approval_url` is a read-only record page on
the website. Never claim it was sent unless the result or `list_reply_requests` shows `sent`.

Sending needs the Plus plan: on Free the tool refuses up front ("Sending replies needs the Plus
plan…") before any form is shown. WhatsApp replies only go to chats where the other person has
written first.

### list_reply_requests({ state?, limit: 1..50 = 20 })

```json
[{ "approval_id": "…", "approval_url": "…", "provider": "telegram", "chat_ref": "cr1.…", "chat_title": "Ana B.",
   "text": "final text, as edited", "state": "failed", "created_at": "…", "decided_at": "…",
   "error": "Telegram did not confirm the send. It may or may not have been delivered; check the chat in Telegram. It was not retried.",
   "ambiguous": true }]
```

`state`: `pending`, `sending`, `sent`, `failed`, `rejected` or `withdrawn`. Only `sent` means
sent. `failed` carries `error` and `ambiguous`: `false` means nothing was delivered; `true`
means it may or may not have been delivered (no confirmation): tell the user to check the chat,
and never request it again automatically. `sending` that never resolves is also reported as an
ambiguous failure, never retried.

### cancel_reply_request({ approval_id })

Withdraws one of your pending requests (for example, it is stale). Returns `{approval_id, state:
"withdrawn"}`, or a `note` when it is no longer pending (already decided) or does not exist.

## Privacy (the user decides; assistants can only propose)

### get_privacy_settings()

The mode (`blocklist`: hide listed chats; `allowlist`: show only listed chats), how many rules
exist, and `manage_url`. Hidden chats are invisible to every connected assistant.

### propose_privacy_rules({ mode?, rules: [{ chat_ref, decision: "allow" | "block", reason }] })

1 to 200 rules, each with a one-line `reason`. The app shows the proposed rules in a form in
the chat. Accept applies all of them (and the mode) at once and returns `{proposal_id, state:
"accepted", rules_applied, mode_changed}`; decline returns `state: "rejected"` and nothing
changes. Unanswered, it returns `state: "pending"` (proposals expire after 7 days). Never say
rules are applied unless the state is `accepted`. The user can also add or remove rules by hand
on the website's Privacy page.

## Prompts

| Prompt | What it does |
|---|---|
| `catch_me_up` | `catch_up`, then `get_mentions`; a summary by chat, most urgent first; no drafts unless asked |
| `draft_replies` | Finds what needs a reply, drafts in the user's tone, shows drafts first, requests approval only for confirmed ones |
| `classify_chats_for_privacy` | Sorts chats into work, personal, family, sensitive; asks what assistants may see; calls `propose_privacy_rules` once |

## Errors

| Text (starts with) | Meaning and what to do |
|---|---|
| `Telegram is not connected. …` / `WhatsApp is not connected. Ask the user to open <url> and scan the QR code…` | Show the (sensitive) link to the user only; wait for them; `connection_status`; retry once |
| `This chat is hidden by the user's privacy settings. It cannot be read, searched or replied to.` | Respect it: do not look for it another way or guess its contents |
| `Rate limit: at most 30 BotChatter calls per minute. Wait a minute, then continue.` | Stop, wait a minute, retry once; use fewer, broader calls (`catch_up`) |
| `Telegram is rate-limiting this account. Try again in N seconds/minutes/hours.` | Flood wait: stop, tell the user, retry once after N |
| `The Telegram session has ended. Connect again to continue.` | `connect_account` for a fresh link |
| `Could not reach Telegram. Please try again.` | Transient: retry once after a few seconds |
| HTTP 401 on `/mcp` | Sign-in expired or revoked: sign in again |
| `This assistant app can't show approval forms (MCP elicitation), …` | `request_reply_approval` and `propose_privacy_rules` only: nothing was sent, drafted or changed. Tell the user to use an app that supports approval forms (Grok Bot, Cursor) |
| `Sending replies needs the Plus plan. …` | Nothing was drafted or sent; pass on the upgrade link |
| `invalid_grant`: `Encryption keys changed; connect this assistant again.` (token refresh) | The account's key was reset and the grant revoked: sign in again (`/mcp`; an agent runs `signup` and `authorize` again with its recovery code) |

A `chat_ref` from another account, or an edited one, is rejected: always use the value a tool
returned.
