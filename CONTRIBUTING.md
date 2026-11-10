# Contributing

This repository holds only the BotChatter plugin for Grok Bot, ChatGPT / Dots, Claude Code, Codex and Cursor (skill, commands,
MCP configuration and the agent sign-up scripts). The BotChatter service and its MCP server
live in a separate repository.

- Pull requests: keep them small, one intent each. Run `claude plugin validate .` and
  `sh test/script-tests.sh` before opening one.
- A change to `scripts/agent-signup.sh` needs the same change in `scripts/agent-signup.ps1`.
- A change to the server behaviour the skill describes lands in the service first; update
  `skills/botchatter/`, `AGENTS-snippet.md` and the README's status table when it is live.
- Privacy wording: never describe the service as "end-to-end encrypted" or "zero-knowledge".
- Bump `version` in both `.claude-plugin/plugin.json` and `.codex-plugin/plugin.json` when a
  change should reach installed plugins.
- Never commit secrets, tokens, emailed codes or account ids.

Contributions are accepted under the repository's licence, [MIT](LICENSE).
