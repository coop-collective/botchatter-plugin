---
description: Get a link to connect your Telegram account (QR code) to Social Connect and show it
argument-hint: "[telegram|whatsapp]"
---

Get a connect link from the Social Connect MCP server and show it to the person. Follow the
`social-connect` skill.

1. Provider: `$ARGUMENTS` if it is `telegram` or `whatsapp`, else `telegram`.
2. Call `connection_status` on the `social-connect` MCP server. If the server is missing or
   answers unauthorized, tell the person to sign in first with
   `claude mcp login plugin:social-connect:social-connect` (or `/mcp`, then pick
   `plugin:social-connect:social-connect`), and stop. If that provider is already `connected`,
   say so (name and @username) and ask whether they still want a new link; stop unless they do.
3. Call `connect_account({ provider })`. On an error (for example "WhatsApp is coming soon"),
   show its message and stop.
4. Show `connect_url` prominently, here only, then in three lines at most: it is valid for 30
   minutes and also unlocks their encrypted data for 2 hours, so it is for them only (never
   post or forward it); open it, read the disclosure, and scan the QR code with
   Telegram on the phone under **Settings → Devices → Link Desktop Device** (on the phone itself,
   tap the `tg://` link instead); tell me when it is done.
5. When they say it is done, call `connection_status` and confirm the connected account. Do not
   read any chats unless they ask.

Never print or paste tokens, and never write the link to a file, issue, commit or log. Do not
open the link yourself. "Rate limit: at most 30 Social Connect calls per minute": wait a minute,
then retry once.
