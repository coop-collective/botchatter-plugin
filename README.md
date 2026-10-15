# Social Connect plugin for Claude Code and Codex

Social Connect lets your AI assistant read your own Telegram and personal WhatsApp chats and
propose replies that you approve yourself. It is a hosted remote MCP server: you sign in with an
email code, connect Telegram or WhatsApp by scanning a QR code, and then ask your assistant to catch you
up, find a chat or draft a reply. A reply is sent only after you approve it in the Social
Connect web app, and then exactly once; reads never mark your messages as read, and you choose
which chats assistants can see. Your messages, contacts and
connection credentials are encrypted with a key that only you, and the AI apps you connect, can
unlock; we don't keep that key. We connect to WhatsApp only while you're using your assistant;
messages that arrive while you're away are fetched next time, within WhatsApp's limits.

**WhatsApp support is beta:** it has not yet been tested against a real account.

This plugin connects Claude Code or Codex to that server and teaches the agent how to use it:
when to read (only when you ask), how much (bounded reads), how to summarize, how to propose a
reply without pressuring you, how to handle "not connected" and Telegram rate limits, and how
an autonomous agent with its own mailbox can sign itself up.

## Install

**Claude Code**

```bash
claude plugin marketplace add coop-collective/social-connect-plugin
claude plugin install social-connect@social-connect
```

**Codex**

```bash
codex plugin marketplace add coop-collective/social-connect-plugin
codex plugin add social-connect@social-connect
```

**Updating.** Claude Code: `claude plugin marketplace update social-connect`, then
`claude plugin update social-connect@social-connect`. Codex: `codex plugin marketplace upgrade
social-connect`, then `codex plugin add social-connect@social-connect`.

## Sign in and connect Telegram or WhatsApp

The plugin registers one MCP server, `social-connect`, at `https://staging.cooposio.com/mcp` over
HTTP with OAuth (no header, no token in a file). Sign in once:

```bash
claude mcp login plugin:social-connect:social-connect   # or /mcp inside a session
codex mcp login social-connect                          # Codex keeps the credential in the OS keychain
```

A browser tab opens: enter your email and the 6-digit code it sends you, then approve the
assistant. The first time, it shows a recovery code once: save it in a password manager (it
unlocks your data in a new browser). If no Telegram account is connected yet, the button reads **Allow and connect
Telegram**: read the disclosure, then scan the QR code with Telegram on your phone
(**Settings → Devices → Link Desktop Device**), or tap the `tg://` link if you are on the phone.
The browser then returns you to your assistant. Skipped it? Run `/social-connect:connect`.

**WhatsApp (beta):** `/social-connect:connect whatsapp` (or "Allow and connect WhatsApp" when
signing in). Open the link on a computer or a second screen, not on your phone, then in
WhatsApp on the phone go to **Settings → Linked devices → Link a device** and scan the QR code.
WhatsApp only has the messages that arrived while it was connected, so older history may be
missing; the assistant will say so.

A connect link is valid for 30 minutes and also unlocks your encrypted data for 2 hours, so
keep it to yourself.

## What it adds

| Piece | What it does |
|---|---|
| Skill `social-connect` | Loaded when you ask about your Telegram or WhatsApp messages, connecting an account, or Social Connect: the tools, the sign-in and connect flow, agent sign-up, and etiquette (ask first, at most 20 chats and 30 messages per call, summarize rather than dump, never pressure you to approve, give the connect link when not connected, wait out rate limits). |
| `/social-connect:connect [telegram\|whatsapp]` | Gets a 30-minute connect link from the MCP server and shows it to you only, with the QR steps. |
| `/social-connect:host <url>` | Uses a custom host (self-hosted, local or staging) for the MCP server and agent sign-up, saved across sessions; `--reset` goes back to the default. |
| `.mcp.json` | The `social-connect` MCP server (HTTP, OAuth) at the plugin's `mcp_url` option (default `https://staging.cooposio.com/mcp`). Codex reads `.codex-plugin/plugin.json` and the literal `.codex-mcp.json` instead. |
| `scripts/agent-signup.sh`, `.ps1` | Headless sign-up for an autonomous agent with its own mailbox (below). |
| `AGENTS-snippet.md` | The same guidance, compact, to paste into an `AGENTS.md` for agents without plugins (Cursor, Copilot, Gemini CLI). |

## Tools

| Tool | What it does |
|---|---|
| `connection_status` | Which accounts are connected, and WhatsApp history import progress |
| `connect_account({provider})` | A 30-minute link (with a 2-hour device unlock) for you to open and scan the QR code |
| `catch_up({provider?, since?, max_chats, per_chat})` | One call for "what's new": active chats since the last catch-up, each with its latest messages |
| `get_mentions({provider?, limit})` | Messages that @mention you or reply to you |
| `list_recent_chats({limit ≤ 20, provider?})` | Your most recent chats across Telegram and WhatsApp |
| `find_chats({query, type?, provider?})` | Any chat or group by name, not only recent ones |
| `get_chat_info({chat_ref})` | A group's description and members, or the other person in a private chat |
| `find_contacts({query, provider?})` | People by name, username or number (phone numbers masked) |
| `read_recent_messages({chat_ref, limit ≤ 30, before?})` | `{provider, messages, sync?}` for one chat, paging back with `before`; never marks anything read. WhatsApp's `sync.state: "partial"` means older messages may be missing |
| `get_message_context({chat_ref, message_id})` | The conversation around one message |
| `search_messages({query, provider?, chat_ref?, type?})` | Search all chats or one chat |
| `get_media({chat_ref, message_id})` | Opens one photo, voice note or file (up to 5 MB); nothing is stored |
| `request_reply_approval({chat_ref, text})` | A pending reply you review, edit, and approve or reject in the web app; approved, it is sent once, exactly as approved |
| `list_reply_requests({state?})` | What happened to requested replies: pending, sending, sent, failed (maybe `ambiguous`), rejected, withdrawn |
| `cancel_reply_request({approval_id})` | Withdraws a pending reply request |
| `get_privacy_settings()` | Your blocklist or allowlist mode and how many rules exist |
| `propose_privacy_rules({mode?, rules})` | Proposes chats to hide or allow; nothing changes until you accept at `review_url` |

MCP prompts: `catch_me_up`, `draft_replies`, `classify_chats_for_privacy`. Chats you hide are
invisible to every connected assistant, and an assistant can only propose privacy rules.

## Agent sign-up (autonomous agents)

An agent that has its own mailbox (Grok, a hosted bot, any autonomous agent) can create and own a
Social Connect account without a browser, then give its human a link to connect Telegram:

```bash
sh scripts/agent-signup.sh signup agent@example.org --agent-name "Example Agent"
printf '%s\n' "<code from the email>" | sh scripts/agent-signup.sh authorize --code -
sh scripts/agent-signup.sh connect          # prints connect_url for the human
sh scripts/agent-signup.sh status
sh scripts/agent-signup.sh call catch_up '{"max_chats":10}'
```

It needs only `sh`, `curl` and `openssl`: it registers an OAuth client, builds a PKCE S256
authorize URL (scope `telegram`), trades the emailed code through `POST /api/agent/authorize`,
exchanges the authorization code at `/oauth/token`, and refreshes the token when it expires.
Secrets travel on stdin, never on a command line, and are never printed. Tokens go to the macOS
Keychain or the Linux Secret Service (`secret-tool`), else to a mode-600 file it names
(`SOCIAL_CONNECT_TOKEN_STORE=file` forces that). The first `authorize` also receives the
account's **recovery code**, shown once by the server: the script stores it the same way, never
prints it, and sends it on every later `authorize` for that address (without it the server
answers 403 `recovery_code_required`). `logout` keeps it; `where` shows where both are stored.
A recovery code saved elsewhere goes in `SOCIAL_CONNECT_RECOVERY_CODE`. `scripts/agent-signup.ps1` is the PowerShell
twin; on Windows it keeps the token and recovery code in files encrypted for the current user
(DPAPI). The raw
HTTP steps are in
[skills/social-connect/references/agent-signup.md](skills/social-connect/references/agent-signup.md).

Only accounts created this way can sign in through it; an address that belongs to an account a
person made in the browser is refused (409).

## Custom host (self-hosted, local, staging)

```bash
/social-connect:host https://social-connect.example.org   # in Claude Code; --reset goes back
```

It runs `agent-signup.sh host <url>`, which checks `<url>/.well-known/oauth-protected-resource/mcp`,
saves the host in `~/.config/social-connect/host` (`$XDG_CONFIG_HOME`; `%APPDATA%` on Windows)
and prints a `claude plugin configure social-connect@social-connect --values-stdin` line that sets
the plugin's `mcp_url`. Restart Claude Code and sign in with `/mcp`. `SOCIAL_CONNECT_WEB=<url>`
overrides the host for one run. Codex substitutes neither `${VAR}` nor `${user_config.*}` in a
plugin's MCP file, so it gets its own manifest with a literal URL; for another host add one by
hand (`codex mcp add social-connect-custom --url <url>`).

## Without a plugin

- **Claude (claude.ai, Desktop):** Settings → Connectors → Add custom connector → paste the MCP URL.
- **Another MCP client:** `claude mcp add --transport http social-connect <url>` or
  `codex mcp add social-connect --url <url>`, and paste `AGENTS-snippet.md` into `AGENTS.md`.

## Development

```bash
claude --plugin-dir .          # load this checkout in Claude Code
claude plugin validate .       # check the marketplace and the plugin manifest
sh test/script-tests.sh        # manifests agree, shellcheck, offline checks of the sign-up script
```

| Path | What |
|---|---|
| `.claude-plugin/marketplace.json` | The marketplace (one plugin, `social-connect`, at the repository root); Claude Code and Codex both read it |
| `.claude-plugin/plugin.json` | Plugin manifest for Claude Code (with the `mcp_url` option) |
| `.codex-plugin/plugin.json`, `.codex-mcp.json` | Codex's manifest (same metadata and version) and its MCP server at a literal URL |
| `.mcp.json` | MCP server for Claude Code (`${user_config.mcp_url}`) |
| `commands/` | `/social-connect:connect`, `/social-connect:host` |
| `skills/social-connect/` | `SKILL.md` plus `references/` (MCP tools, agent sign-up) |
| `scripts/` | `agent-signup.sh` and its PowerShell twin |
| `test/` | Script and manifest checks |

## Status of the server side

| Feature | State |
|---|---|
| MCP OAuth (email code sign-in, DCR and CIMD), 17 tools and 3 prompts, 30 tool calls a minute per account | Staging (`https://staging.cooposio.com`) |
| User-keyed encryption at rest (recovery code, device unlock) | Built (connector HEAD); check staging is deployed |
| Connect Telegram by QR inside the OAuth trip | Staging |
| Agent sign-up (`/api/agent/*`, with the recovery code) | Built; check `GET <host>/api/agent/` answers JSON before relying on it |
| Sending an approved reply (once, exactly as approved; ambiguous failures never retried) | Built (connector HEAD); check staging is deployed |
| Privacy rules (blocklist or allowlist; assistants propose, the user accepts) | Built (connector HEAD) |
| Personal WhatsApp (connect by QR, merged chat list, partial-history `sync`) | **Beta**: built (connector HEAD), not yet tested against a real account |

Update the skill, the snippet and this table when those change.

## License

[MIT](LICENSE). Copyright 2026 Coop.

## Grok Bot and Cursor

This repository is also a Cursor plugin (`.cursor-plugin/plugin.json`, `mcp.json`, `assets/logo.svg`), which is the
format Grok Bot uses for connectors.

- **Grok Bot:** Connect apps → Add → custom MCP server `https://staging.cooposio.com/mcp`, then sign in with your email
  code and approve. In chat, say "connect my Telegram" (or WhatsApp): Social Connect shows the risks, then a QR code right
  in the chat to scan from your phone (Telegram: Settings → Devices → Link Desktop Device; WhatsApp: Settings → Linked
  devices). Telegram can also connect with your phone number and login code. If anything needs a browser (Telegram
  two-step password), you get a link.
- **Cursor:** add `{"mcpServers":{"social-connect":{"url":"https://staging.cooposio.com/mcp"}}}` to `~/.cursor/mcp.json`,
  or install this repo as a plugin.
- The connector uses OAuth (no tokens in this repo). Privacy policy: https://staging.cooposio.com/privacy-policy ·
  Terms: https://staging.cooposio.com/terms
