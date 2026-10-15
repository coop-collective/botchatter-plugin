# Agent sign-up (headless)

For an autonomous agent with **its own mailbox** that creates and owns a Social Connect account
without a browser, then hands its human a link to connect Telegram. Only accounts created this
way can sign in through it: an address that belongs to an account a person created in a browser
answers `409 browser_account`, and that person signs in through normal MCP OAuth instead.

Prefer the bundled script (`../../scripts/agent-signup.sh`, Windows `agent-signup.ps1`): it does
all of this, keeps every secret off command lines and out of its output, and stores the tokens in
the OS keychain. The raw flow below is for an agent that cannot run it. `<web>` is the host
(default `https://staging.cooposio.com`); `GET <web>/api/agent/` describes the same steps.

## 1. Ask for a code

```http
POST <web>/api/agent/signup
Content-Type: application/json

{"email": "agent@example.org", "agent_name": "Example Agent"}
```

`200 {"status":"code_sent","expires_in_seconds":600}`. The email's subject is
`<code> is your Social Connect code`. Codes expire after 10 minutes, allow 5 guesses and work
once. `429`: wait the time the message states (30 seconds between codes for one address; a
per-IP limit of 5 a minute) and try again.

## 2. Register a client and build a PKCE authorize URL

```http
POST <web>/oauth/register
Content-Type: application/json

{"client_name":"Example Agent","redirect_uris":["http://127.0.0.1:8976/callback"],
 "grant_types":["authorization_code","refresh_token"],"response_types":["code"],
 "token_endpoint_auth_method":"none"}
```

Keep `client_id`. Make a random `code_verifier` (43+ characters of base64url),
`code_challenge = base64url(sha256(code_verifier))` and a random `state`, then:

```
<web>/authorize?response_type=code&client_id=<id>&redirect_uri=<encoded redirect>
  &scope=telegram&state=<state>&code_challenge=<challenge>&code_challenge_method=S256
  &resource=<encoded <web>/mcp>
```

Nothing opens this URL in a browser; the server reads it in the next step. The redirect URI is
never contacted.

## 3. Trade the code for an authorization code

```http
POST <web>/api/agent/authorize
Content-Type: application/json

{"email":"agent@example.org","code":"123456","authorize_url":"<the URL from step 2>"}
```

`200 {"redirect_to":"http://127.0.0.1:8976/callback?code=…&state=…"}`. Check that `state`
matches. `400 invalid_grant`: wrong or expired code (start again at step 1).

## 4. Exchange it for tokens

```http
POST <web>/oauth/token
Content-Type: application/x-www-form-urlencoded

grant_type=authorization_code&code=<code>&redirect_uri=<redirect>&client_id=<id>
&code_verifier=<verifier>&resource=<web>/mcp
```

`access_token` (Bearer, bound to `<web>/mcp`) and `refresh_token`. Refresh with
`grant_type=refresh_token&refresh_token=…&client_id=…&resource=…`; the refresh token rotates, so
store the new one. Keep both in a secret store; never print or log them.

## 5. Use the MCP server and connect Telegram

Streamable HTTP at `<web>/mcp` with `Authorization: Bearer <access_token>` and
`Accept: application/json, text/event-stream`: `initialize`, `notifications/initialized`, then
`tools/call`. Call `connect_account({"provider":"telegram"})` and give `connect_url` (valid 30
minutes) to your human only: they open it and scan the QR code with Telegram (Settings → Devices
→ Link Desktop Device, or tap the `tg://` link on the phone). When they say it is done,
`connection_status` shows `connected` and the read tools work. The etiquette in `SKILL.md`
applies to an agent exactly as to an assistant: the chats are the human's.
