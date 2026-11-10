# BotChatter plugin

The open-source **BotChatter plugin** connects your assistant to your own Telegram and
personal WhatsApp accounts. It bundles the MCP connection, account-setup instructions,
and a skill for reading chats, catching up, searching, managing Telegram folders, and
drafting replies. Every reply requires your confirmation before it is sent.

- **Website and setup prompts:** [botchatter.ai](https://botchatter.ai/start)
- **Public source:** [coop-collective/botchatter-plugin](https://github.com/coop-collective/botchatter-plugin)
- **Download:** [plugin ZIP](https://github.com/coop-collective/botchatter-plugin/archive/refs/heads/main.zip)
- **Production MCP endpoint:** `https://botchatter.ai/mcp`
- **License:** [MIT](LICENSE)

This repository contains the plugin, skills, and helper scripts. The hosted service is
separate. You do not need access to its private source repository to install this plugin.

## Install

**Install and enable the plugin before connecting accounts.** Download the ZIP or use
`git clone https://github.com/coop-collective/botchatter-plugin.git`, then follow the
instructions for your assistant below. Marketplace installers can fetch the source directly.
A downloaded folder or an MCP connection alone is not a completed plugin installation:
verify that the host has enabled BotChatter and loaded its `botchatter` skill.

Open [the setup page](https://botchatter.ai/start), choose your assistant and accounts, and
copy the generated prompt. It requires plugin installation before sign-in and pairing.
If your host cannot import plugins, complete the required host/admin setup before continuing.
The public GitHub repository does not imply a listing in an assistant's public directory.

### Grok Bot

1. Open [BotChatter setup](https://botchatter.ai/start?assistant=grok) and choose the bot's
   inbox or your own email. Download the plugin using the link on that page.
2. Paste the setup prompt into Grok Bot. It tells the bot to read this README, install the
   repository through a supported plugin-import mechanism, and load
   [`skills/botchatter/SKILL.md`](skills/botchatter/SKILL.md).
3. Confirm that BotChatter is installed and enabled in the host. The package includes
   `.cursor-plugin/plugin.json` for compatible Cursor/Grok plugin hosts. If your Grok Bot
   version does not offer repository/plugin import, have it explain the supported install
   path available to your account and pause. Adding a custom MCP app alone does not install
   the skill. Do not assume that a Cursor desktop install also installs a cloud Bot's plugin.
4. Continue with the generated prompt. In **bot inbox** mode, Grok requests an email code
   and receives an agent key. In **my email** mode, it redeems the one-time setup code from
   the signed-in setup page. Save the returned Authorization header in the host's secret
   settings and configure the installed plugin's MCP connection; never commit the key or
   paste it into chat. Reuse that connection rather than adding a duplicate MCP server.
5. The bot verifies `connection_status`, shows the pairing disclosures, and connects your
   selected accounts after you agree. Scan the QR code and let it check for completion.

The plugin does not bypass host approvals or team policies. Grok's connected apps and
computer credentials have different access models; see
[Work with Grok Bot](https://cursor.com/docs/grok-bot/work).

### ChatGPT / Dots

Dots use plugins installed and enabled in **ChatGPT**. A local Codex CLI install or a ZIP
on your computer alone does not make the plugin available to a cloud Dot.

For a ChatGPT workspace with GitHub marketplace imports:

1. A workspace admin opens **Admin → Plugins → Add → Import marketplace**.
2. Enter `https://github.com/coop-collective/botchatter-plugin` as the source. Leave the path
   empty; the marketplace is at the repository root. Import and review BotChatter.
3. Install and enable BotChatter from your workspace's Plugins directory, then authenticate
   its MCP connection through OAuth using your email.
4. Start a new conversation if needed, make the plugin available to your Dot, and paste the
   prompt from [BotChatter setup](https://botchatter.ai/start?assistant=dots).
5. Ask the Dot to verify the installed skill and call `connection_status` before pairing.

For a personal account, use a supported plugin import/install tool if your ChatGPT
surface provides one. If it does not, the Dot must explain that limitation and pause;
this repository is not a promise of a public-directory listing. Manually creating a
Developer mode MCP app supplies tools but does not install this plugin's bundled skill.

Official guidance: [GitHub marketplace import](https://learn.chatgpt.com/docs/enterprise/plugin-management),
[plugins](https://learn.chatgpt.com/docs/plugins), and
[Dots app access](https://learn.chatgpt.com/docs/dots/computers-and-apps#connect-apps).

### Claude Code

```sh
claude plugin marketplace add coop-collective/botchatter-plugin
claude plugin install botchatter@botchatter
```

Start a new session. Open `/mcp`, select the plugin's BotChatter connection, and sign in
through OAuth. Then ask Claude to use the BotChatter skill and call `connection_status`.
These commands are for **Claude Code**, not an assertion that claude.ai imports repositories.

### Codex

```sh
codex plugin marketplace add coop-collective/botchatter-plugin
codex plugin add botchatter@botchatter
```

Start a new session, enable the plugin, and authenticate its MCP connection when prompted.
Check that the `botchatter` skill and tools are available. This installs into that Codex
host; use the ChatGPT instructions above for a cloud Dot.

### Cursor

Import the repository into a supported team marketplace, or use a local plugin install:

```sh
git clone https://github.com/coop-collective/botchatter-plugin.git ~/.cursor/plugins/local/botchatter
```

If the destination already exists, update that checkout instead of overwriting it. Reload
Cursor and check **Customize** for BotChatter's skill and MCP connection. Local imports
must be allowed by your workspace policy. Authenticate the MCP connection through OAuth.
See [Cursor's plugin installation guide](https://cursor.com/docs/plugins#test-plugins-locally).

### Other MCP clients

Use a client that can install this plugin format and load its skill. An MCP-only client
can reach the server, but that is a tools-only integration, not the plugin installation
required by the landing-page setup flow. [`AGENTS-snippet.md`](AGENTS-snippet.md) is a
manual integration reference for developers, not an installation-success check.

## Connect your accounts

After installation and authentication, ask: “Use BotChatter to connect my Telegram and
WhatsApp.” The assistant calls `start_connect`, shows the risks, waits for your agreement,
and then shows a QR code. Telegram also supports phone-number login.

- **Telegram:** Settings → Devices → Link Desktop Device. If Telegram requires a two-step
  password, enter it on the returned browser page; never give it to the assistant in chat.
- **WhatsApp:** Settings → Linked devices → Link a device. Display the QR code on another
  screen so your phone can scan it. WhatsApp support is beta and uses an unofficial client.

A successful link and a completed history import are separate states. The Accounts page
updates WhatsApp history progress automatically and shows **Sync complete** when reported
by the connector. Recent history depth depends on what your phone supplies. A partial
sync is not proof that older messages do not exist.

Ask your assistant to call `get_web_sign_in_link` when you want to open your account or
settings. It returns a one-time link without making you repeat email sign-in. Save your
recovery code securely when it is first issued; do not put it in the plugin repository.

## Use BotChatter

- “Catch me up on my chats since yesterday.”
- “Find the message about Friday's appointment.”
- “Show my Telegram folders and watch my Work folder for new messages.”
- “Draft a reply to Alice.” The assistant shows the chat and exact text and waits for your
  approval before `send_reply` sends the draft.
- “Hide my work chats from assistants.” The assistant proposes the precise privacy changes
  for your approval.

Reads do not mark messages as read. Your messages and credentials are encrypted under
user-specific keys; the hosted service processes authorized requests with the keys
presented for those requests. WhatsApp reads and searches cover captured/imported data
and must report incomplete history honestly.

See the [skill](skills/botchatter/SKILL.md) and [tool reference](skills/botchatter/references/mcp-tools.md).
To enable approved replies, ask for a settings sign-in link and turn on **Let my assistant
app approve sends** under **Settings → Reply permissions**. Keep per-send confirmation
in your assistant. The website's Replies page is a record, not a send button.

## Agent scripts and custom hosts

The landing-page Grok prompt uses the current agent-key setup flow. The repository also
includes shell and PowerShell helpers for an agent with its own mailbox using the OAuth
sign-up flow. See [agent sign-up](skills/botchatter/references/agent-signup.md).

```sh
sh scripts/agent-signup.sh signup agent@example.org --agent-name "Example Agent"
# Provide the emailed code through stdin, not a command-line argument:
sh scripts/agent-signup.sh authorize --code -
sh scripts/agent-signup.sh status
```

The scripts store credentials in the OS credential store when available, with a protected
file fallback. Their existing `SOCIAL_CONNECT_*` environment variables and storage paths
remain supported for compatibility; the public plugin name is **BotChatter**.

New installs default to production. To use a separate staging account, choose
`https://staging.botchatter.ai/mcp` explicitly. In Claude Code, `/botchatter:host <origin>`
changes the plugin option. Other hosts must update their installed MCP connection using
their supported configuration mechanism. Keep staging and production credentials separate.

## Update and contribute

```sh
# Claude Code
claude plugin marketplace update botchatter
claude plugin update botchatter@botchatter

# Codex
codex plugin marketplace upgrade botchatter
codex plugin add botchatter@botchatter
```

Restart the relevant session after updating. Workspace imports follow their marketplace's
sync policy; local Git installs can use `git pull --ff-only` in the plugin checkout.

Run `npm test` for offline manifest/script checks, and `claude plugin validate .` to validate
the Claude package. See [CONTRIBUTING.md](CONTRIBUTING.md). No account credentials belong
in this repository.

[Privacy policy](https://botchatter.ai/privacy-policy) · [Terms](https://botchatter.ai/terms) ·
[Support](mailto:support@botchatter.ai)
