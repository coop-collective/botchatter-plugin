---
description: Get a link to connect your Telegram or WhatsApp (beta) account by QR code to BotChatter and show it
argument-hint: "[telegram|whatsapp]"
---

Get a connect link from the BotChatter MCP server and show it to the person. Follow the
`botchatter` skill.

1. Provider: `$ARGUMENTS` if it is `telegram` or `whatsapp`, else `telegram`.
2. Call `connection_status` on the `botchatter` MCP server. If the server is missing or
   answers unauthorized, tell the person to sign in first with
   `claude mcp login plugin:botchatter:botchatter` (or `/mcp`, then pick
   `plugin:botchatter:botchatter`), and stop. If that provider is already `connected`,
   say so (name and @username) and ask whether they still want a new link; stop unless they do.
3. Call `connect_account({ provider })`. On an error, show its message and stop.
4. Show `connect_url` prominently, here only, then in three lines at most: it is valid for 30
   minutes and also unlocks their encrypted data for 2 hours, so it is for them only (never
   post or forward it); open it, read the disclosure, and scan the QR code. Telegram: on the
   phone under **Settings → Devices → Link Desktop Device** (on the phone itself, tap the `tg://`
   link instead). WhatsApp: open the link on a computer or second screen, not the phone, then
   **Settings → Linked devices → Link a device**; add that WhatsApp support is beta and not yet
   tested against a real account. Tell me when it is done.
5. When they say it is done, call `connection_status` and confirm the connected account. Do not
   read any chats unless they ask.

Never print or paste tokens, and never write the link to a file, issue, commit or log. Do not
open the link yourself. "Rate limit: at most 30 BotChatter calls per minute": wait a minute,
then retry once.
