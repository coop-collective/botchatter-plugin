---
description: Use a custom BotChatter host (self-hosted, local or staging) for the MCP server and agent sign-up, saved across sessions
argument-hint: "<url> | --reset"
---

Point this plugin's MCP server and the agent sign-up script at the BotChatter host in
`$ARGUMENTS` (for example `https://staging.botchatter.ai` or `http://localhost:8787`), or back to
the default `https://staging.botchatter.ai` with `--reset`. With no argument, show the current
host and stop.

Script: `sh "${CLAUDE_PLUGIN_ROOT}/scripts/agent-signup.sh"` (on Windows without Git Bash:
`powershell -NoProfile -ExecutionPolicy Bypass -File "${CLAUDE_PLUGIN_ROOT}/scripts/agent-signup.ps1"`,
same subcommands, `-Reset` for `--reset`).

1. `<script> host <url>` (or `<script> host --reset`, or `<script> host` to show). It checks
   that `<url>/.well-known/oauth-protected-resource/mcp` answers, saves the host in
   `<config>/social-connect/host` (`$XDG_CONFIG_HOME`, else `~/.config`; `%APPDATA%` on Windows)
   so later agent sign-up runs use it when `SOCIAL_CONNECT_WEB` is unset, and prints `mcp_url:`
   and a `claude_code:` line. On `cannot reach`, report it and stop.
2. Run the `claude_code:` line as printed: it saves the MCP URL in this plugin's `mcp_url`
   option (Claude Code keeps it in the user settings). If it says no installed plugin has the id
   `botchatter@botchatter`, find the id with `claude plugin list` and run it with that id.
3. Tell the person, in three lines at most: restart Claude Code, then run `/mcp` and sign in to
   `plugin:botchatter:botchatter` on the new host (each host has its own accounts); if
   they also added a BotChatter server by hand (`claude mcp add`), disable one of the two in
   `/mcp`, because both offer the same tool names. Codex reads a literal URL, so it uses the
   printed `codex:` line instead.

Never print a token or keychain contents. Do not edit shell profiles or `settings.json` by hand.
