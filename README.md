# Social Connect plugin for Claude Code and Codex

Social Connect lets your AI assistant read your own Telegram chats (personal WhatsApp is coming)
and propose replies that you approve yourself. It is a hosted remote MCP server: you sign in with
an email code, connect Telegram by scanning a QR code, and then ask your assistant to catch you
up, summarize a chat or draft a reply. Nothing is ever sent unless you approve it in the Social
Connect web app, and reads never mark your messages as read. For Telegram, your messages,
contacts and connection credentials are encrypted with a key that only you, and the AI apps you
connect, can unlock; we don't keep that key. Personal WhatsApp is coming soon.

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

## Sign in and connect Telegram

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
A connect link is valid for 30 minutes and also unlocks your encrypted data for 2 hours, so
keep it to yourself.

## What it adds

| Piece | What it does |
|---|---|
| Skill `social-connect` | Loaded when you ask about your Telegram messages, connecting an account, or Social Connect: the tools, the sign-in and connect flow, agent sign-up, and etiquette (ask first, at most 20 chats and 30 messages per call, summarize rather than dump, never pressure you to approve, give the connect link when not connected, wait out rate limits). |
| `/social-connect:connect [telegram]` | Gets a 30-minute connect link from the MCP server and shows it to you only, with the QR steps. |
| `/social-connect:host <url>` | Uses a custom host (self-hosted, local or staging) for the MCP server and agent sign-up, saved across sessions; `--reset` goes back to the default. |
| `.mcp.json` | The `social-connect` MCP server (HTTP, OAuth) at the plugin's `mcp_url` option (default `https://staging.cooposio.com/mcp`). Codex reads `.codex-plugin/plugin.json` and the literal `.codex-mcp.json` instead. |
| `scripts/agent-signup.sh`, `.ps1` | Headless sign-up for an autonomous agent with its own mailbox (below). |
| `AGENTS-snippet.md` | The same guidance, compact, to paste into an `AGENTS.md` for agents without plugins (Cursor, Copilot, Gemini CLI). |

## Tools

| Tool | What it does |
|---|---|
| `connection_status` | Which accounts are connected |
| `connect_account({provider})` | A 30-minute link (with a 2-hour device unlock) for you to open and scan the QR code |
| `list_recent_chats({limit ≤ 20})` | Your most recent chats, newest first |
| `read_recent_messages({chat_ref, limit ≤ 30})` | Recent text messages in one chat; never marks them read |
| `request_reply_approval({chat_ref, text})` | A pending reply you review, edit, approve or reject in the web app. Sending is disabled on staging |

## Agent sign-up (autonomous agents)

An agent that has its own mailbox (Grok, a hosted bot, any autonomous agent) can create and own a
Social Connect account without a browser, then give its human a link to connect Telegram:

```bash
sh scripts/agent-signup.sh signup agent@example.org --agent-name "Example Agent"
printf '%s\n' "<code from the email>" | sh scripts/agent-signup.sh authorize --code -
sh scripts/agent-signup.sh connect          # prints connect_url for the human
sh scripts/agent-signup.sh status
sh scripts/agent-signup.sh call list_recent_chats '{"limit":10}'
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
| MCP OAuth (email code sign-in, DCR and CIMD), the five tools, 30 tool calls a minute per account | Staging (`https://staging.cooposio.com`) |
| User-keyed encryption at rest for Telegram (recovery code, device unlock) | Built (connector HEAD); check staging is deployed |
| Connect Telegram by QR inside the OAuth trip | Staging |
| Agent sign-up (`/api/agent/*`, with the recovery code) | Built; check `GET <host>/api/agent/` answers JSON before relying on it |
| Sending an approved reply | **Disabled** on staging (approval is recorded, nothing is sent) |
| Personal WhatsApp | **Coming** |

Update the skill, the snippet and this table when those change.

## License

[MIT](LICENSE). Copyright 2026 Coop.
