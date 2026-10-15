---
name: social-connect
description: Read the user's own Telegram and personal WhatsApp chats (WhatsApp in beta) through the Social Connect MCP server, and propose replies that are sent only after the user approves each one. Use when the user asks to catch up on, summarize, triage or search their Telegram or WhatsApp messages, find a chat, contact or mention, open a photo or file from a chat, draft or follow up on a reply, choose which chats assistants may see (privacy rules), connect Telegram or WhatsApp to their assistant, sign in to Social Connect, or when an autonomous agent with its own mailbox needs a Social Connect account (agent sign-up). Also use on a Social Connect tool error (not connected, rate-limited, unauthorized). Not for sending messages directly, bulk messaging, or other people's accounts.
---

# Social Connect

Social Connect is a hosted remote MCP server (`social-connect`) that lets an assistant read the
**user's own** Telegram and personal WhatsApp chats and propose replies. A reply is sent only
after the user approves it in the Social Connect web app, and then exactly once. **WhatsApp is beta**: it has not yet been tested against a real
account, so say so when the user connects it or relies on it. Default host: `https://staging.cooposio.com` (MCP at `/mcp`); a custom
host is set with `/social-connect:host <url>`.

## Tools (server `social-connect`, 17)

| Need | Tool |
|---|---|
| Is anything connected? | `connection_status()`: call first |
| Connect an account | `connect_account({provider})` → `connect_url` for the human (sensitive) |
| What's new? | **`catch_up({provider?, since?, max_chats ≤ 20, per_chat ≤ 10})`**: one call, chats with activity since the last catch_up, each with its latest messages |
| What needs my answer? | `get_mentions({provider?, limit ≤ 30})`: @mentions and replies to the user |
| Find a chat by name | `find_chats({query, type?, provider?, limit ≤ 20})`, not only recent ones |
| Latest chats | `list_recent_chats({limit ≤ 20, provider?})` |
| Group details, members | `get_chat_info({chat_ref, member_limit ≤ 100})` |
| Find a person | `find_contacts({query, provider?, limit ≤ 50})`: phones masked; a 1:1 `chat_ref` when one exists |
| Read one chat | `read_recent_messages({chat_ref, limit ≤ 30, before?})` → `{provider, messages, sync?}`; page back with `before` |
| Around one message | `get_message_context({chat_ref, message_id, before ≤ 15, after ≤ 15})` |
| Search | `search_messages({query, provider?, chat_ref?, limit ≤ 20, type?})`: every word must match |
| Open a photo or file | `get_media({chat_ref, message_id})`: up to 5 MB, nothing stored |
| Propose a reply | `request_reply_approval({chat_ref, text})` → pending, `approval_url` |
| Follow up on replies | `list_reply_requests({state?, limit ≤ 50})`, `cancel_reply_request({approval_id})` |
| Privacy | `get_privacy_settings()`, `propose_privacy_rules({mode?, rules})` → `review_url` |

MCP prompts (slash commands in clients that support them): `catch_me_up`, `draft_replies`,
`classify_chats_for_privacy`. Full schemas, results and error texts:
[references/mcp-tools.md](references/mcp-tools.md).

`chat_ref` is an opaque signed token bound to this user's account (`cr1.…` Telegram, `wr1.…`
WhatsApp): pass it back unchanged, never invent or edit one. Say which app a chat is from when
you summarize across both.

**WhatsApp history is partial.** WhatsApp only has the messages that arrived while it was
connected. When `sync.state` is `"partial"`, older messages may be missing: say so ("I can only
see messages since <oldest_synced>") instead of claiming there are none or that a conversation
started there. Never infer silence from a partial sync. The same holds for `catch_up` and
`search_messages` on WhatsApp: they only see captured messages.

## (a) A person in Claude Code or Codex

1. **Sign in once.** The plugin registers the MCP server over HTTP with OAuth; no token is ever
   put in a file. If the tools are missing or answer 401, ask the person to run
   `claude mcp login plugin:social-connect:social-connect` (or `/mcp` inside a session, then pick
   `plugin:social-connect:social-connect`); in Codex, `codex mcp login social-connect`. A browser
   opens: they enter their email, type the 6-digit code from the email, and approve the assistant.
   The first time, the page shows a **recovery code once**: tell them to save it somewhere safe
   (a password manager). It unlocks their encrypted data in a new browser; without it, a lost
   browser means connecting again from scratch. Never ask them to paste it into the chat.
2. **Connect Telegram in the same trip.** If no Telegram account is connected yet, the consent
   button reads "Allow and connect Telegram". They read the disclosure, then scan the QR code
   with Telegram on their phone (**Settings → Devices → Link Desktop Device**), or, on the phone
   itself, tap the `tg://` link. The browser then returns them to the assistant.
3. **WhatsApp (beta):** call `connect_account({provider: "whatsapp"})` (or
   `/social-connect:connect whatsapp`; the sign-in page also offers "Allow and connect WhatsApp").
   The link opens `/connect/whatsapp`, which shows a QR code. In WhatsApp on the phone:
   **Settings → Linked devices → Link a device**, then scan. The QR code must be shown on a
   computer or another screen, **not on the same phone** that scans it. Mention that WhatsApp
   support is beta and not yet tested against a real account.
4. **Later, or if it was skipped:** `/social-connect:connect`, or call `connect_account` and show
   the `connect_url` (valid 30 minutes) to that person only. Wait until they say it is done, then
   `connection_status`. The link is sensitive (see "Connect links" below).

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
printf '%s\n' "$CODE" | sh $S authorize --code -   # trades it for tokens; stores them and the recovery code
sh $S connect                                 # prints connect_url: give it to your human
sh $S status                                  # after they say it is done
sh $S call catch_up '{"max_chats":10}'        # any tool; exit 3 when the tool reports an error
```

The raw HTTP flow, for an agent that cannot run the script, is in
[references/agent-signup.md](references/agent-signup.md): `POST /api/agent/signup {email,
agent_name}` → register a client at `/oauth/register` → PKCE S256 `/authorize` URL with scope
`telegram` → `POST /api/agent/authorize {email, code, authorize_url}` → `redirect_to` carries the
code → exchange at `/oauth/token` → call `/mcp` → `connect_account` → link to the human.

**Recovery code.** The first successful `authorize` for an account creates its encryption key and
returns a `recovery_code` once. The script stores it like the token (Keychain / `secret-tool` /
mode-600 file), never prints it, sends it automatically on every later `authorize` for that
address (a new client, a new machine after copying it, or after the key changed), and `logout`
keeps it. Without it, a later `authorize` gets **403 `recovery_code_required`** and the emailed
code is used up: if the code was saved elsewhere, run `signup` again and `authorize` with
`SOCIAL_CONNECT_RECOVERY_CODE` set in the environment (never on a command line); if it is lost,
that account cannot be authorized again, so sign up with another address. `sh $S where` shows
where the token and recovery code are stored without printing them.

Rules: only for an address the agent itself controls; an address that belongs to a
browser-created account answers 409 (that person signs in through (a)). Never print, log or
paste the access token, refresh token, recovery code or emailed code.

## Connect links are sensitive

A `connect_url` (`/link/cl2.…`) is valid for 30 minutes and carries a **2-hour device unlock**
for the account's encrypted data. Give it only to the account's own human, in this private
conversation (or the agent's private channel to its owner). Never post it publicly, in a group
chat, an issue, a commit, a log or a file, and never send it to anyone else. Do not open it
yourself. If it may have leaked, say so and get a fresh one later rather than reusing it.

## (c) Etiquette: reading someone's private messages

- **Ask before reading.** Reading private chats needs a clear request from the user in this
  conversation ("catch me up on Telegram", "what did Ana say?"). Do not browse chats on your own
  initiative, and say which chat you are about to open when it is not obvious.
- **Use the right tool, few calls.** "What's new" → `catch_up` (then `get_mentions` for what
  needs an answer), not `list_recent_chats` followed by `read_recent_messages` on each chat. A
  chat by name → `find_chats`. One search hit → `get_message_context`. Every call counts toward
  the 30-a-minute limit.
- **Bounded reads.** At most 20 chats and 30 messages per call (the server enforces this too).
  Start small, and read more or page back with `before` only when the user asks. No sweeping
  every chat, no history export.
- **Ask before opening media or contacts unrelated to the request.** `get_media` and
  `find_contacts` / `get_chat_info` members are for what the user asked about. Phone numbers are
  masked by default; do not try to unmask them, and repeat a full number only when the user
  asked for that person's number.
- **Summarize, do not dump.** Give who said what and what needs an answer, in a few lines per
  chat. Quote a message verbatim only when the user asks or the exact wording matters. Do not
  copy message contents into files, issues, commits or other tools unless asked.
- **Replies are sent only after the human approves.** Show the draft first and call
  `request_reply_approval` only for drafts the user confirms. It creates a pending reply: give
  the `approval_url` and say it is sent once, exactly as approved (they may edit it), only after
  they approve it in the web app. **Never say it was sent until `list_reply_requests` shows state
  `sent`** (check when the user asks, not in a polling loop). `rejected` or `withdrawn`: nothing
  was sent, do not re-request unless asked. `failed` with `ambiguous: false`: it was not
  delivered; say why. **`failed` with `ambiguous: true`: it may or may not have been delivered:
  tell the user to check the chat in the app, and never request it again automatically.**
  Withdraw a stale pending request with `cancel_reply_request`. WhatsApp replies only go to
  chats where the other person has written first. Never pressure, nag or hurry the person to
  approve; one mention is enough. One reply per request: no bulk replies, no messages to chats
  the user did not choose.
- **Hidden chats stay hidden.** The user can hide chats (blocklist) or show only some
  (allowlist). "This chat is hidden by the user's privacy settings" means exactly that: do not
  look for it another way (search, contacts, mentions, another provider), and do not guess its
  contents. You may only propose rules: `propose_privacy_rules` (or the
  `classify_chats_for_privacy` prompt) returns a `review_url`; nothing changes until the user
  accepts there. Never say rules are applied.
- **Not connected.** A tool error "Telegram is not connected. Ask the user to open <url> …"
  (or "WhatsApp is not connected. …") already contains a connect link (sensitive, as above):
  show it to the user only, explain the QR step (Telegram: Settings → Devices → Link Desktop
  Device, or tap the `tg://` link on the phone; WhatsApp: Settings → Linked devices → Link a
  device, scanning a QR code shown on another screen), wait until they say it is done, then
  `connection_status` and retry once. `state: revoked` means the app ended the session (for
  example, the linked device was removed): call `connect_account` for a fresh link. WhatsApp
  `state: locked` means it is paired and reconnects on the next read.
- **Rate limits and flood waits.** "Rate limit: at most 30 Social Connect calls per minute"
  (per account), "Telegram is rate-limiting this account. Try again in N
  seconds/minutes/hours", or a sign-in 429 ("wait 30 seconds", "Wait a minute"): stop calling,
  tell the user, and retry once after the stated time (a minute for the 30-calls limit). Plan
  reads so one request stays well under 30 calls. Never retry in a tight loop, and do not
  wait silently for longer than a minute or two: say how long and continue with other work or end
  the turn. A wait of an hour or more: report it and stop.
- **401 / unauthorized.** The sign-in expired or was revoked: ask the person to sign in again
  (`/mcp`); an agent re-runs `signup` and `authorize`.
- **"Encryption keys changed; connect this assistant again"** (an `invalid_grant` when the token
  is refreshed, after the account's key was reset): the grant is revoked. A person signs in again
  with `/mcp`; an agent runs `signup` and `authorize` again (the stored recovery code is sent).

## What to say about privacy

Social Connect never sends without the owner's approval of that exact reply in the web app,
reads do not mark messages as read, and the user decides which chats assistants can see. For Telegram and WhatsApp you may say, in these words: "Your messages, contacts and
connection credentials are encrypted with a key that only you, and the AI apps you connect, can
unlock. We don't keep that key." Also: "When you disconnect, we delete the key, and anything left
behind is permanently unreadable", and "To work, our servers process your messages in memory
while your assistant is using them. We don't store them in a form we can read." For WhatsApp,
also: "We connect to WhatsApp only while you're using your assistant. Messages that arrive while
you're away are fetched next time, within WhatsApp's limits." WhatsApp support is beta (not yet
tested against a real account); say so rather than promising it works.

Never say "end-to-end encrypted" or "zero-knowledge" (or "zero-access"), "we can never see your
messages", "only you can unlock" (without "and the AI apps you connect"), "even if we're hacked
your data is safe", or that Cloudflare cannot access it.
