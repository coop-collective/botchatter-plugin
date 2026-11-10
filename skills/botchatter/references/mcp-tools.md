# BotChatter MCP tools

Server: `botchatter`, streamable HTTP at `<host>/mcp` (default `https://botchatter.ai/mcp`),
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

### get_web_sign_in_link({page?})

`page` is `"accounts"` (default) or `"settings"`. Returns
`{status:"ok", sign_in_url, expires_in_seconds:900}`. Call immediately when the user asks to
open BotChatter, their account, dashboard or settings. The MCP credential already identifies
the account, including a Grok Bot email account. No browser login, email code or sign-up is
needed. Give the private link directly to the user; it opens the account automatically,
works once for 15 minutes, and must never be opened by the assistant.

For disabled sending, use `page:"settings"`. The user enables **Let my assistant app approve
sends** under **Reply permissions** and selects **Save reply permissions**. Each reply still
needs confirmation in the assistant app. The website cannot send a draft.

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
- WhatsApp (beta, unofficial linked device): the link opens `/connect/whatsapp`;
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

## Sending (draft, the user confirms in the chat, send)

All approval happens in the assistant app's chat; the BotChatter website only keeps a read-only
record (Replies page). These are the only two sending tools.

### draft_reply({ chat_ref, text: 1..4000 chars })

Queues one draft and sends nothing (no form, not destructive). Returns:

```json
{ "draft_id": "…", "chat_title": "Ana B.", "provider": "telegram", "text": "exact text", "state": "pending",
  "expires_at": "…", "next": "Show the user the chat and exact text and ask them to confirm. When they say yes, call send_reply with this draft_id." }
```

A further account of a provider adds `account: {id, label}`. Show the user the chat and the exact
text and ask them to confirm. To change the text, draft again; an unsent draft expires after 15
minutes. Sending needs the Pro plan: on Free this refuses up front ("Sending messages needs the
Pro plan. Nothing was drafted or sent; …"). WhatsApp messages only go to chats where the other
person has written first.

### send_reply({ draft_id, user_confirmation: 1..500 chars })

Annotated destructive and open-world, so apps with a tool-call approval step show it to the user
first. Call it only after the user's own next message explicitly said yes to that draft, and pass
their words verbatim in `user_confirmation`. Sends exactly the draft's text to its chat, from the
account it was drafted for, once:

```json
{ "draft_id": "…", "state": "sent", "chat_title": "Ana B.", "provider": "telegram", "text": "exact text", "sent_at": "…" }
```

Or `state: "failed"` with `error` and `ambiguous`: `false` means nothing was delivered; `true`
means it may or may not have been delivered (no confirmation): tell the user to check the chat.
A failed send is never retried. Refused, with `Nothing was sent: …`, when the draft is unknown or
another user's, already sent, being sent, failed, withdrawn, expired (15 minutes), or the plan
no longer includes sending. Never claim it was sent unless the state is `sent`.

## Privacy (the user decides)

### get_privacy_settings()

The mode (`blocklist`: hide listed chats; `allowlist`: show only listed chats), how many rules
exist, and `manage_url`. Hidden chats are invisible to every connected assistant.

### apply_privacy_rules({ mode?, rules: [{ chat_ref, decision: "allow" | "block", reason }], user_confirmation })

Applies the rules (and the mode) at once, only after the user saw the exact list of chats and
changes in the chat and explicitly said yes; pass their words in `user_confirmation`. Annotated
destructive. Returns `{proposal_id, state: "accepted", rules_applied, mode_changed, rules,
manage_url}`; it appears in the Privacy page's history.

## Folders (Telegram)

Folder changes run only after the user's explicit yes in the chat, and only when **Let my assistant app approve
sends** is on (the same gate as sending). Chats the user hid never appear in a folder's results and cannot be
added or removed. WhatsApp has no folders a linked device can read.

### list_folders({ provider = "telegram", account?, query? })

`{ supported: true, folders: [{ folder_ref, title, shared, emoji, chosen_chats, includes_all, excludes, account? }] }`.
`query` matches folder names (case-insensitive). `includes_all` lists the chat kinds the folder takes in by rule:
`contacts`, `non_contacts`, `groups`, `channels`, `bots`. `shared` folders were joined from an invite link, and
their chats can only be changed in Telegram. With `provider: "whatsapp"`: `{ supported: false, folders: [], note }`.

### list_folder_chats({ folder_ref, limit: 1..50 = 20 })

`{ folder, chats: ChatSummary[], truncated }`: the folder's chats as Telegram computes them, newest activity
first.

### read_folder_messages({ folder_ref, max_chats: 1..20 = 10, per_chat: 1..10 = 5 })

`{ folder, chats: [{ provider, chat, messages }], truncated }`.

### watch_messages({ folder_ref | chat_ref, cursor?, max_chats: 1..20 = 10, per_chat: 1..10 = 5 })

Pass exactly one of `folder_ref` and `chat_ref`. Returns `{ chats: [{ chat, messages }], new_messages, cursor,
coverage, folder? }`. Only messages newer than `cursor` are returned; without a cursor you get the current newest
window. Store the new `cursor` for the next run. A cursor is bound to this user and this folder or chat, and it
lasts 7 days. A foreign, edited or expired cursor fails with "This cursor is not valid…": start again without one.
Each run sees at most `per_chat` messages per chat, so poll often enough.

### create_folder({ title: 1..12 chars, chat_refs: [] , account?, user_confirmation })

`{ created: true, folder }`. All chats must be Telegram chats of one account. A duplicate name is refused.

### update_folder({ folder_ref, title?, add_chat_refs?, remove_chat_refs?, user_confirmation })

`{ updated: true, folder }`. A removed chat leaves the folder only; if it was in by a rule (e.g. "all groups"),
it is excluded instead.

### delete_folder({ folder_ref, confirm_token?, user_confirmation? })

1. **Without `confirm_token`:** deletes nothing. Returns `{ deleted: false, folder, chats_in_folder, confirm_token,
   next }`. The token lasts 10 minutes.
2. **With `confirm_token` and `user_confirmation`,** after the user said yes: `{ deleted: true, title }`.

No chat or message is ever deleted. A token for another folder or user, or an expired one, is refused with
"Nothing was deleted: …".

## Prompts

| Prompt | What it does |
|---|---|
| `catch_me_up` | `catch_up`, then `get_mentions`; a summary by chat, most urgent first; no drafts unless asked |
| `draft_replies` | Finds what needs a reply, writes replies in the user's tone; for each one the user wants: `draft_reply`, show it, `send_reply` after the user's yes |
| `classify_chats_for_privacy` | Sorts chats into work, personal, family, sensitive; asks what assistants may see; shows the exact changes and calls `apply_privacy_rules` after the user's yes |

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
| `Sending messages needs the Pro plan. …` | Nothing was drafted or sent; pass on the upgrade link |
| `Nothing was sent: …` (from `send_reply`) | The draft was unknown, already sent, failed, expired or withdrawn, or the plan changed: tell the user; draft again only if they still want to send |
| `… is paused: the user's plan reads fewer accounts …` | Pass on the upgrade link; do not retry |
| `invalid_grant`: `Encryption keys changed; connect this assistant again.` (token refresh) | The account's key was reset and the grant revoked: sign in again (`/mcp`; an agent runs `signup` and `authorize` again with its recovery code) |

A `chat_ref` from another account, or an edited one, is rejected: always use the value a tool
returned.
