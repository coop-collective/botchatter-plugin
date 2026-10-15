# Social Connect MCP tools

Server: `social-connect`, streamable HTTP at `<host>/mcp` (default `https://staging.cooposio.com/mcp`),
protected by OAuth 2.1 (PKCE S256, dynamic client registration at `/oauth/register`, Client ID
Metadata Documents). Scope: `telegram` (it covers both providers). An unauthenticated request answers 401 with a
`WWW-Authenticate` challenge pointing to `/.well-known/oauth-protected-resource/mcp`.

Every tool returns one text item holding JSON, or an error (`isError: true`) whose text is a
readable message.

## connection_status()

```json
{ "telegram": { "state": "connected", "account": { "name": "Ana B.", "username": "anab" } },
  "whatsapp": { "state": "locked", "account": { "name": "Ana", "phone": "+44 •••• ••12" }, "messages_synced": 812 } }
```

Telegram `state`: `connected`, `not_connected` or `revoked` (Telegram ended the session;
reconnect). WhatsApp `state` (beta): `not_connected`, `connecting` (pairing in progress),
`connected`, `locked` (paired; reconnects on the next read) or `revoked` (the linked device was
removed; reconnect).

## connect_account({ provider: "telegram" | "whatsapp" = "telegram" })

```json
{ "provider": "telegram", "connect_url": "https://…/link/…", "expires_in_seconds": 1800 }
```

A signed 30-minute link (`/link/cl2.…`) for the account's own human only. It also carries a
2-hour device unlock for the account's encrypted data, so treat it as a secret: never post it
publicly or anywhere but the private conversation with that person. Opening it gives a
connect-only session: it can connect, view or disconnect the provider account, but cannot
approve replies or authorize assistants.
Telegram: the page shows a QR code; the human scans it in Telegram under Settings → Devices →
Link Desktop Device, or taps the `tg://` link on the phone that has Telegram.

WhatsApp (beta, not yet tested against a real account): the link opens `/connect/whatsapp`
(disclosure, consent, then a self-refreshing QR code). The human scans it in WhatsApp under
Settings → Linked devices → Link a device. The QR code must be on a computer or another screen,
not on the phone that scans it.

## list_recent_chats({ limit: 1..20 = 10, provider?: "telegram" | "whatsapp" })

```json
[{ "provider": "telegram", "chat_ref": "cr1.…", "title": "Ana B.", "type": "private", "unread_count": 2, "last_message_at": "2026-10-14T18:03:00Z" },
 { "provider": "whatsapp", "chat_ref": "wr1.…", "title": "Family", "type": "group", "unread_count": null, "last_message_at": "2026-10-14T17:40:00Z" }]
```

Newest first, merged across connected providers unless `provider` is given. WhatsApp
`unread_count` is always null. Telegram archived chats are excluded.

## read_recent_messages({ chat_ref, limit: 1..30 = 20 })

```json
{ "provider": "whatsapp",
  "messages": [{ "id": "3EB0…", "from": "Ana", "date": "2026-10-14T18:03:00Z", "text": "See you at 7?" }],
  "sync": { "state": "partial", "oldest_synced": "2026-10-12T09:00:00Z", "note": "…" } }
```

Same shape for both providers (`id` is a number on Telegram, a string on WhatsApp; Telegram has
no `sync`). Newest first. Text only (media and service messages skipped), so it may return fewer
than `limit`. Never marks messages as read. WhatsApp only has what arrived while it was
connected: `sync.state: "partial"` means older messages may be missing, so say so instead of
claiming there are none.

## request_reply_approval({ chat_ref, text: 1..4000 chars })

```json
{ "approval_id": "…", "approval_url": "https://…/approvals/…", "state": "pending",
  "note": "Not sent. The owner must approve in the web app; sending is disabled in staging." }
```

The owner reviews the provider, account, chat and exact text, may edit it, and approves or
rejects. Approving applies once to that exact text. On staging, approving records the decision
and sends nothing.

## Errors

| Text (starts with) | Meaning and what to do |
|---|---|
| `Telegram is not connected. …` / `WhatsApp is not connected. Ask the user to open <url> and scan the QR code with WhatsApp…` | Show the (sensitive) link to the user only; wait for them; `connection_status`; retry once |
| `Rate limit: at most 30 Social Connect calls per minute. Wait a minute, then continue.` | Per-account limit on tool calls: stop, wait a minute, retry once |
| `Telegram is rate-limiting this account. Try again in N seconds/minutes/hours.` | Flood wait: stop, tell the user, retry once after N |
| `The Telegram session has ended. Connect again to continue.` | `connect_account` for a fresh link |
| `Could not reach Telegram. Please try again.` | Transient: retry once after a few seconds |
| HTTP 401 on `/mcp` | Sign-in expired or revoked: sign in again |
| `invalid_grant`: `Encryption keys changed; connect this assistant again.` (token refresh) | The account's key was reset and the grant revoked: sign in again (`/mcp`; an agent runs `signup` and `authorize` again with its recovery code) |

`chat_ref` from another account, or an edited one, is rejected: always use the value the last
`list_recent_chats` returned.
