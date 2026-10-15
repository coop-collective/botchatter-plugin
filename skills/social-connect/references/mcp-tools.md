# Social Connect MCP tools

Server: `social-connect`, streamable HTTP at `<host>/mcp` (default `https://staging.cooposio.com/mcp`),
protected by OAuth 2.1 (PKCE S256, dynamic client registration at `/oauth/register`, Client ID
Metadata Documents). Scope: `telegram`. An unauthenticated request answers 401 with a
`WWW-Authenticate` challenge pointing to `/.well-known/oauth-protected-resource/mcp`.

Every tool returns one text item holding JSON, or an error (`isError: true`) whose text is a
readable message.

## connection_status()

```json
{ "telegram": { "state": "connected", "account": { "name": "Ana B.", "username": "anab" } } }
```

`state` is `connected`, `not_connected` or `revoked` (Telegram ended the session; reconnect).

## connect_account({ provider: "telegram" | "whatsapp" = "telegram" })

```json
{ "provider": "telegram", "connect_url": "https://…/link/…", "expires_in_seconds": 1800 }
```

A signed 30-minute link for the human. Opening it gives a connect-only session: it can connect,
view or disconnect the provider account, but cannot approve replies or authorize assistants.
The page shows a QR code; the human scans it in Telegram under Settings → Devices → Link Desktop
Device, or taps the `tg://` link on the phone that has Telegram. `whatsapp` currently errors with
"WhatsApp is coming soon. Only telegram can be connected right now."

## list_recent_chats({ limit: 1..20 = 10 })

```json
[{ "chat_ref": "…", "title": "Ana B.", "type": "private", "unread_count": 2, "last_message_at": "2026-10-14T18:03:00Z" }]
```

Newest first. Archived chats are excluded.

## read_recent_messages({ chat_ref, limit: 1..30 = 20 })

```json
[{ "id": 4812, "from": "Ana B.", "date": "2026-10-14T18:03:00Z", "text": "See you at 7?" }]
```

Newest first. Text only (link previews included; media and service messages skipped), so it may
return fewer than `limit`. Never marks messages as read.

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
| `Telegram is not connected. Ask the user to open <url> and scan the QR code…` | Show the link; wait for the user; `connection_status`; retry once |
| `Telegram is rate-limiting this account. Try again in N seconds/minutes/hours.` | Flood wait: stop, tell the user, retry once after N |
| `The Telegram session has ended. Connect again to continue.` | `connect_account` for a fresh link |
| `Could not reach Telegram. Please try again.` | Transient: retry once after a few seconds |
| `WhatsApp is coming soon…` | Only Telegram can be connected today |
| HTTP 401 on `/mcp` | Sign-in expired or revoked: sign in again |

`chat_ref` from another account, or an edited one, is rejected: always use the value the last
`list_recent_chats` returned.
