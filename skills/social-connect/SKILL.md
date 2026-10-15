---
name: social-connect
description: Read the user's own Telegram chats (personal WhatsApp coming) through the Social Connect MCP server, and propose replies they approve themselves. Use when the user asks to catch up on, summarize, triage or search their recent Telegram messages, draft a reply to a Telegram chat, connect Telegram (or WhatsApp) to their assistant, sign in to Social Connect, or when an autonomous agent with its own mailbox needs a Social Connect account (agent sign-up). Also use on a Social Connect tool error (not connected, rate-limited, unauthorized). Not for sending messages directly, bulk messaging, or other people's accounts.
---

# Social Connect

Social Connect is a hosted remote MCP server (`social-connect`) that lets an assistant read the
**user's own** Telegram chats and propose a reply that the user approves in the Social Connect
web app. Personal WhatsApp is coming: `connect_account({provider: "whatsapp"})` currently answers
"WhatsApp is coming soon". Default host: `https://staging.cooposio.com` (MCP at `/mcp`); a custom
host is set with `/social-connect:host <url>`.

## Tools (server `social-connect`)

| Tool | Use |
|---|---|
| `connection_status()` | Call first. `{telegram: {state: connected \| not_connected \| revoked, account}}` |
| `connect_account({provider: "telegram"})` | `{connect_url, expires_in_seconds: 1800}`: a link **for the human** to open |
| `list_recent_chats({limit: 1..20 = 10})` | Newest first: `chat_ref`, `title`, `type`, `unread_count`, `last_message_at` |
| `read_recent_messages({chat_ref, limit: 1..30 = 20})` | Text messages only, newest first (`id`, `from`, `date`, `text`). Never marks anything read |
| `request_reply_approval({chat_ref, text})` | Creates a **pending** reply and returns `approval_url`. Nothing is sent |

`chat_ref` is an opaque signed token bound to this user's account: pass it back unchanged, never
invent or edit one. Full schemas and error texts: [references/mcp-tools.md](references/mcp-tools.md).

## (a) A person in Claude Code or Codex

1. **Sign in once.** The plugin registers the MCP server over HTTP with OAuth; no token is ever
   put in a file. If the tools are missing or answer 401, ask the person to run
   `claude mcp login plugin:social-connect:social-connect` (or `/mcp` inside a session, then pick
   `plugin:social-connect:social-connect`); in Codex, `codex mcp login social-connect`. A browser
   opens: they enter their email, type the 6-digit code from the email, and approve the assistant.
2. **Connect Telegram in the same trip.** If no Telegram account is connected yet, the consent
   button reads "Allow and connect Telegram". They read the disclosure, then scan the QR code
   with Telegram on their phone (**Settings → Devices → Link Desktop Device**), or, on the phone
   itself, tap the `tg://` link. The browser then returns them to the assistant.
3. **Later, or if it was skipped:** `/social-connect:connect`, or call `connect_account` and show
   the `connect_url` (valid 30 minutes). Wait until they say it is done, then `connection_status`.

## (b) An autonomous agent signing itself up (headless)

For an agent that has **its own mailbox** (Grok, a hosted bot, any autonomous agent) and no
browser. The agent owns the account; its human only connects Telegram through a link. A person
using Claude Code or Codex never needs this: use (a).

The bundled script does every step with only `sh`, `curl` and `openssl`, sends secrets on stdin,
never prints them, and stores the tokens in the OS keychain (macOS Keychain, or `secret-tool` on
Linux; otherwise a mode-600 file it names). Codex and other agents run it relative to this skill
directory: `../../scripts/agent-signup.sh` (Windows: `../../scripts/agent-signup.ps1`, same
subcommands); in Claude Code, `${CLAUDE_PLUGIN_ROOT}/scripts/agent-signup.sh`.

```bash
S=../../scripts/agent-signup.sh             # relative to this skill directory
sh $S describe                               # optional: the host's own description of the steps
sh $S signup agent@example.org --agent-name "Example Agent"   # registers a client, prepares PKCE, emails a code
# read the 6-digit code from the agent's mailbox (subject "<code> is your Social Connect code")
printf '%s\n' "$CODE" | sh $S authorize --code -   # trades it for tokens; prints only where they are stored
sh $S connect                                 # prints connect_url: give it to your human
sh $S status                                  # after they say it is done
sh $S call list_recent_chats '{"limit":10}'   # any tool; exit 3 when the tool reports an error
```

The raw HTTP flow, for an agent that cannot run the script, is in
[references/agent-signup.md](references/agent-signup.md): `POST /api/agent/signup {email,
agent_name}` → register a client at `/oauth/register` → PKCE S256 `/authorize` URL with scope
`telegram` → `POST /api/agent/authorize {email, code, authorize_url}` → `redirect_to` carries the
code → exchange at `/oauth/token` → call `/mcp` → `connect_account` → link to the human.

Rules: only for an address the agent itself controls; an address that belongs to a
browser-created account answers 409 (that person signs in through (a)). Give the connect link to
the agent's own human only, never post it anywhere public: it lets whoever opens it connect a
Telegram account to this Social Connect account for 30 minutes. Never print, log or paste the
access token, refresh token or emailed code.

## (c) Etiquette: reading someone's private messages

- **Ask before reading.** Reading private chats needs a clear request from the user in this
  conversation ("catch me up on Telegram", "what did Ana say?"). Do not browse chats on your own
  initiative, and say which chat you are about to open when it is not obvious.
- **Bounded reads.** At most 20 chats per `list_recent_chats` and 30 messages per
  `read_recent_messages` (the server enforces this too). Start small (10 chats; 20 messages in
  the chats that matter), and read more only when the user asks. No sweeping every chat, no
  history export.
- **Summarize, do not dump.** Give who said what and what needs an answer, in a few lines per
  chat. Quote a message verbatim only when the user asks or the exact wording matters. Do not
  copy message contents into files, issues, commits or other tools unless asked.
- **Replies need the human.** `request_reply_approval` only creates a pending reply: show the
  draft, give the `approval_url`, and say plainly that nothing is sent until they approve it in
  the web app (and that sending is disabled on staging). Never claim a message was sent. Never
  pressure, nag or hurry the person to approve; one mention is enough, and rejecting is fine.
  One reply per request: no bulk replies, no messages to chats the user did not choose.
- **Not connected.** A tool error "Telegram is not connected. Ask the user to open <url> …"
  already contains the link: show it, explain the QR step (Settings → Devices → Link Desktop
  Device, or tap the `tg://` link on the phone), wait until they say it is done, then
  `connection_status` and retry once. `state: revoked` means Telegram ended the session (for
  example, the device was removed): call `connect_account` for a fresh link.
- **Rate limits and flood waits.** "Telegram is rate-limiting this account. Try again in N
  seconds/minutes/hours", or a sign-in 429 ("wait 30 seconds", "Wait a minute"): stop calling,
  tell the user, and retry once after the stated time. Never retry in a tight loop, and do not
  wait silently for longer than a minute or two: say how long and continue with other work or end
  the turn. A wait of an hour or more: report it and stop.
- **401 / unauthorized.** The sign-in expired or was revoked: ask the person to sign in again
  (`/mcp`); an agent re-runs `signup` and `authorize`.

## What not to say

Social Connect never sends without the owner's approval in the web app, and reads do not mark
messages as read. Do not describe it as "end-to-end encrypted" or "zero-knowledge", and do not
claim the service "can never see" messages: it processes them on its servers to answer your
tool calls. For privacy questions, point to the Social Connect web app's own pages.
