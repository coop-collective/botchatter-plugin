#!/bin/sh
# BotChatter agent sign-up: an autonomous agent with its own mailbox creates and owns a
# BotChatter account without a browser, then hands its human a link to connect Telegram.
# Humans in Claude Code or Codex do not need this: they sign in through MCP OAuth (/mcp).
#
#   agent-signup.sh describe                      what this host's agent API says (GET /api/agent/)
#   agent-signup.sh signup EMAIL [--agent-name NAME]
#                                                  register an OAuth client, prepare PKCE and ask
#                                                  the host to email a 6-digit code to EMAIL
#   agent-signup.sh authorize --code CODE         trade the emailed code for tokens (CODE "-" reads
#                                                  it from stdin) and store them; nothing is printed
#   agent-signup.sh status                        call the connection_status tool
#   agent-signup.sh connect [--provider telegram] call connect_account; prints the link for the human
#   agent-signup.sh call TOOL [JSON_ARGUMENTS]    call any BotChatter MCP tool, print its result
#   agent-signup.sh where                         where the token and recovery code are stored (never
#                                                  the values themselves)
#   agent-signup.sh logout                        forget the stored token for this host (keeps the
#                                                  recovery code)
#   agent-signup.sh host [URL | --reset]          show, save or forget this machine's BotChatter host
#
# Needs only sh, curl and openssl. Secrets (the emailed code, the PKCE verifier, access and refresh
# tokens, the account's recovery code) are sent on stdin, never on a command line, and are never
# printed. Tokens and the recovery code go to the OS keychain (macOS Keychain, or libsecret's
# secret-tool on Linux); without one they go to mode-600 files under <config>/social-connect and
# the script says so. The recovery code is returned once, the first time the account's encryption
# key is created; every later authorize for that account sends it automatically. logout keeps it.
# Settings:
#   SOCIAL_CONNECT_WEB           the BotChatter host for this run; else the host saved with
#                                 `host URL` (<config>/social-connect/host); else the default below
#   SOCIAL_CONNECT_TOKEN_STORE   keychain | file (default: keychain when one works, else file)
#   SOCIAL_CONNECT_RECOVERY_CODE the account's recovery code, when it was saved somewhere else
#                                 (used instead of the stored one; never put it on a command line)
set -u
umask 077

DEFAULT_WEB=https://botchatter.ai
CONFIG_DIR=${XDG_CONFIG_HOME:-$HOME/.config}/social-connect
HOST_FILE=$CONFIG_DIR/host
REDIRECT_URI=http://127.0.0.1:8976/callback
KEYCHAIN_SERVICE=social-connect
RECOVERY_SERVICE=social-connect-recovery
SOCIAL_CONNECT_WEB=${SOCIAL_CONNECT_WEB:-}
SOCIAL_CONNECT_TOKEN_STORE=${SOCIAL_CONNECT_TOKEN_STORE:-}
SOCIAL_CONNECT_RECOVERY_CODE=${SOCIAL_CONNECT_RECOVERY_CODE:-}

say() { printf '%s\n' "$*"; }
warn() { printf 'botchatter: %s\n' "$*" >&2; }
die() { warn "$*"; exit 1; }

saved_host() { [ -f "$HOST_FILE" ] && sed -n '1{s/[[:space:]]*$//;p;}' "$HOST_FILE"; }
if [ -n "$SOCIAL_CONNECT_WEB" ]; then
  WEB=$SOCIAL_CONNECT_WEB WEB_SOURCE=SOCIAL_CONNECT_WEB
elif WEB=$(saved_host) && [ -n "$WEB" ]; then
  WEB_SOURCE="saved in $HOST_FILE"
else
  WEB=$DEFAULT_WEB WEB_SOURCE=default
fi
WEB=${WEB%/}
MCP_URL=$WEB/mcp
HOST_KEY=$(printf '%s' "${WEB#*://}" | tr -c 'A-Za-z0-9.-' '_')
PENDING_FILE=$CONFIG_DIR/pending-$HOST_KEY
TOKEN_FILE=$CONFIG_DIR/token-$HOST_KEY
ACCOUNT_FILE=$CONFIG_DIR/account-$HOST_KEY

for tool in curl openssl; do
  command -v "$tool" >/dev/null 2>&1 || die "$tool is required"
done

TMP=$(mktemp -d "${TMPDIR:-/tmp}/botchatter.XXXXXX") || die "cannot create a temporary directory"
trap 'rm -rf "$TMP"' EXIT
trap 'exit 130' INT TERM

# A string or number field of a flat JSON object (the server's own answers).
json_field() {
  printf '%s' "$1" | tr -d '\n' |
    sed -n "s/.*\"$2\"[[:space:]]*:[[:space:]]*\"\\([^\"]*\\)\".*/\\1/p;t
s/.*\"$2\"[[:space:]]*:[[:space:]]*\\([0-9][0-9]*\\).*/\\1/p"
}

# A query parameter, still percent-encoded (which is also how a form body wants it).
query_param() {
  printf '%s' "${1#*\?}" | tr '&' '\n' | sed -n "s/^$2=//p" | sed -n 1p
}

# Percent-encode a URL or identifier for a query string or form body.
form_escape() {
  printf '%s' "$1" | sed -e 's/%/%25/g' -e 's/ /%20/g' -e 's/!/%21/g' -e 's/#/%23/g' -e 's/\$/%24/g' \
    -e 's/&/%26/g' -e "s/'/%27/g" -e 's/+/%2B/g' -e 's/,/%2C/g' -e 's|/|%2F|g' -e 's/:/%3A/g' \
    -e 's/;/%3B/g' -e 's/=/%3D/g' -e 's/?/%3F/g' -e 's/@/%40/g'
}

# JSON string value; we only accept plain text without quotes, backslashes or control characters.
json_safe() {
  case $1 in *[\"\\]* ) return 1 ;; esac
  [ "$(printf '%s' "$1" | tr -d '[:cntrl:]')" = "$1" ]
}

b64url() { openssl base64 -A | tr '+/' '-_' | tr -d '='; }

# curl with the body on stdin; prints the body and leaves the HTTP status in $TMP/status.
post_stdin() { # URL CONTENT_TYPE  (body on stdin)
  curl -sS --max-time 30 -o "$TMP/body" -w '%{http_code}' -X POST -H "Content-Type: $2" \
    -H 'Accept: application/json' --data-binary @- "$1" >"$TMP/status" || die "cannot reach $1"
  cat "$TMP/body"
}
status_code() { cat "$TMP/status"; }

explain_error() { # BODY CONTEXT
  desc=$(json_field "$1" error_description)
  err=$(json_field "$1" error)
  die "$2 failed (HTTP $(status_code))${err:+: $err}${desc:+ - $desc}"
}

# --- token storage ----------------------------------------------------------------------------

store_kind() {
  case $SOCIAL_CONNECT_TOKEN_STORE in
    file) say file; return ;;
    keychain | '') ;;
    *) die "SOCIAL_CONNECT_TOKEN_STORE must be keychain or file" ;;
  esac
  if [ "$(uname -s)" = Darwin ] && command -v security >/dev/null 2>&1; then say macos-keychain
  elif command -v secret-tool >/dev/null 2>&1; then say secret-tool
  else say file
  fi
}

# Generic secret store. SERVICE and ACCOUNT name the keychain item; FILE is the mode-600 fallback.
# secret_save reads the value on stdin and prints where it went.
secret_save() { # SERVICE ACCOUNT FILE LABEL
  value=$(cat)
  case $(store_kind) in
    macos-keychain)
      if printf 'add-generic-password -U -s "%s" -a "%s" -l "%s" -w "%s"\n' "$1" "$2" "$4" "$value" |
          security -i >/dev/null 2>&1 &&
        security find-generic-password -s "$1" -a "$2" >/dev/null 2>&1; then
        rm -f "$3"
        say "macOS Keychain (service $1, account $2)"
        return
      fi ;;
    secret-tool)
      if printf '%s' "$value" | secret-tool store --label="$4" service "$1" account "$2" >/dev/null 2>&1; then
        rm -f "$3"
        say "the Secret Service keyring (service $1, account $2)"
        return
      fi ;;
  esac
  mkdir -p "$CONFIG_DIR" && chmod 700 "$CONFIG_DIR"
  { printf '%s\n' "$value" >"$3" && chmod 600 "$3"; } || die "cannot write $3"
  if [ "$SOCIAL_CONNECT_TOKEN_STORE" = file ]; then say "$3 (mode 600)"
  else say "$3 (mode 600; no OS keychain was usable)"
  fi
}

secret_load() { # SERVICE ACCOUNT FILE  (prints the value for capture; callers never echo it)
  if [ -f "$3" ]; then sed -n 1p "$3"; return; fi
  case $(store_kind) in
    macos-keychain) security find-generic-password -s "$1" -a "$2" -w 2>/dev/null ;;
    secret-tool) secret-tool lookup service "$1" account "$2" 2>/dev/null ;;
  esac
  return 0
}

secret_exists() { # SERVICE ACCOUNT FILE
  [ -f "$3" ] && return 0
  case $(store_kind) in
    macos-keychain) security find-generic-password -s "$1" -a "$2" >/dev/null 2>&1 ;;
    secret-tool) secret-tool lookup service "$1" account "$2" >/dev/null 2>&1 ;;
    *) return 1 ;;
  esac
}

secret_forget() { # SERVICE ACCOUNT FILE
  rm -f "$3"
  case $(store_kind) in
    macos-keychain) security delete-generic-password -s "$1" -a "$2" >/dev/null 2>&1 ;;
    secret-tool) secret-tool clear service "$1" account "$2" >/dev/null 2>&1 ;;
  esac
  return 0
}

# Tokens: "ACCESS REFRESH CLIENT_ID", one item per host.
save_tokens() { secret_save "$KEYCHAIN_SERVICE" "$HOST_KEY" "$TOKEN_FILE" "BotChatter ($HOST_KEY)"; }
forget_tokens() { secret_forget "$KEYCHAIN_SERVICE" "$HOST_KEY" "$TOKEN_FILE"; }
load_tokens() {
  value=$(secret_load "$KEYCHAIN_SERVICE" "$HOST_KEY" "$TOKEN_FILE")
  [ -n "$value" ] || die "not signed in to $WEB: run signup, then authorize (or set SOCIAL_CONNECT_WEB)"
  # shellcheck disable=SC2086
  set -- $value
  ACCESS=${1:-} REFRESH=${2:-} CLIENT_ID=${3:-}
  [ -n "$ACCESS" ] || die "the stored token for $WEB is unreadable: run logout, then signup again"
}

# Recovery code: one item per host and account email. Shown once by the server at first sign-up and
# required to authorize that account again; it is never printed and logout keeps it.
recovery_names() { # EMAIL -> sets RC_ACCOUNT and RC_FILE
  RC_ACCOUNT="$HOST_KEY/$1"
  RC_FILE=$CONFIG_DIR/recovery-$HOST_KEY-$(printf '%s' "$1" | tr -c 'A-Za-z0-9.-' '_')
}

# --- commands ---------------------------------------------------------------------------------

cmd_describe() {
  body=$(curl -sS --max-time 20 -H 'Accept: application/json' -w '\n%{http_code}' "$WEB/api/agent/") ||
    die "cannot reach $WEB"
  code=$(printf '%s' "$body" | sed -n '$p')
  case $code in
    200) printf '%s\n' "$body" | sed '$d' ;;
    *) die "$WEB does not offer agent sign-up (GET /api/agent/ answered HTTP $code)" ;;
  esac
}

cmd_signup() {
  email='' agent_name=''
  while [ $# -gt 0 ]; do
    case $1 in
      --agent-name) [ $# -ge 2 ] || die "--agent-name needs a value"; agent_name=$2; shift 2 ;;
      --email) [ $# -ge 2 ] || die "--email needs a value"; email=$2; shift 2 ;;
      -*) die "signup: unknown option $1" ;;
      *) email=$1; shift ;;
    esac
  done
  case $email in *@*.*) ;; *) die "signup: pass the agent's own email address" ;; esac
  { json_safe "$email" && json_safe "$agent_name"; } || die "signup: email and agent name must not contain quotes or backslashes"
  client_name=${agent_name:-BotChatter agent}

  # 1. Register a public OAuth client (dynamic client registration).
  reg=$(printf '{"client_name":"%s","redirect_uris":["%s"],"grant_types":["authorization_code","refresh_token"],"response_types":["code"],"token_endpoint_auth_method":"none"}' \
    "$client_name" "$REDIRECT_URI" | post_stdin "$WEB/oauth/register" application/json)
  case $(status_code) in 200 | 201) ;; *) explain_error "$reg" "client registration" ;; esac
  client_id=$(json_field "$reg" client_id)
  [ -n "$client_id" ] || die "client registration returned no client_id"

  # 2. PKCE S256 and the authorize URL (the server reads it; no browser opens).
  verifier=$(openssl rand 32 | b64url)
  challenge=$(printf '%s' "$verifier" | openssl dgst -sha256 -binary | b64url)
  state=$(openssl rand -hex 16)
  authorize_url="$WEB/authorize?response_type=code&client_id=$(form_escape "$client_id")&redirect_uri=$(form_escape "$REDIRECT_URI")&scope=telegram&state=$state&code_challenge=$challenge&code_challenge_method=S256&resource=$(form_escape "$MCP_URL")&login_hint=$(form_escape "$email")"

  # 3. Ask for the emailed code.
  sent=$(printf '{"email":"%s","agent_name":"%s"}' "$email" "$agent_name" |
    post_stdin "$WEB/api/agent/signup" application/json)
  case $(status_code) in
    200) ;;
    409) die "$email belongs to an account a person created in a browser: sign in through MCP OAuth (/mcp) instead" ;;
    429) explain_error "$sent" "signup (rate-limited; wait the time it states, then retry)" ;;
    *) explain_error "$sent" "signup" ;;
  esac

  mkdir -p "$CONFIG_DIR" && chmod 700 "$CONFIG_DIR"
  {
    say "email=$email"
    say "agent_name=$agent_name"
    say "client_id=$client_id"
    say "verifier=$verifier"
    say "state=$state"
    say "authorize_url=$authorize_url"
  } >"$PENDING_FILE" || die "cannot write $PENDING_FILE"
  chmod 600 "$PENDING_FILE"

  say "web: $WEB ($WEB_SOURCE)"
  say "code_sent: $email (expires in $(json_field "$sent" expires_in_seconds) seconds)"
  say "next: read the 6-digit code from that mailbox, then run: agent-signup.sh authorize --code <code>"
}

pending() { sed -n "s/^$1=//p" "$PENDING_FILE" | sed -n 1p; }

cmd_authorize() {
  code=''
  while [ $# -gt 0 ]; do
    case $1 in
      --code) [ $# -ge 2 ] || die "--code needs a value"; code=$2; shift 2 ;;
      *) die "authorize: unknown argument $1 (use --code CODE, or --code - to read it from stdin)" ;;
    esac
  done
  [ "$code" = - ] && { IFS= read -r code || true; }
  code=$(printf '%s' "$code" | tr -d ' \t\r')
  case $code in '' | *[!0-9]*) die "authorize: --code takes the 6-digit code from the email" ;; esac
  [ -f "$PENDING_FILE" ] || die "no sign-up in progress for $WEB: run signup EMAIL first"
  email=$(pending email) agent_name=$(pending agent_name) client_id=$(pending client_id)
  verifier=$(pending verifier) state=$(pending state) authorize_url=$(pending authorize_url)

  recovery_names "$email"
  recovery=$SOCIAL_CONNECT_RECOVERY_CODE recovery_source=SOCIAL_CONNECT_RECOVERY_CODE
  if [ -z "$recovery" ]; then
    recovery=$(secret_load "$RECOVERY_SERVICE" "$RC_ACCOUNT" "$RC_FILE") recovery_source=stored
  fi
  json_safe "$recovery" || die "authorize: the recovery code must not contain quotes or backslashes"

  answer=$({
    printf '{"email":"%s","code":"%s","authorize_url":"%s","agent_name":"%s"' "$email" "$code" "$authorize_url" "$agent_name"
    [ -n "$recovery" ] && printf ',"recovery_code":"%s"' "$recovery"
    printf '}'
  } | post_stdin "$WEB/api/agent/authorize" application/json)
  case $(status_code) in
    200) ;;
    400) explain_error "$answer" "authorize (a wrong or expired code: run signup again for a new one)" ;;
    403)
      if [ -z "$recovery" ]; then
        die "authorize refused (recovery_code_required): $email already has an encryption key, created at its first sign-up, and this machine has no recovery code for it. The emailed code is now used up. If the recovery code was saved elsewhere, run signup again and authorize with SOCIAL_CONNECT_RECOVERY_CODE set in the environment (never on a command line). Without it this account cannot be authorized again; sign up with another address."
      fi
      die "authorize refused (recovery_code_required): the recovery code ($recovery_source) was not accepted for $email. The emailed code is now used up. Run signup again and authorize with the right code in SOCIAL_CONNECT_RECOVERY_CODE." ;;
    *) explain_error "$answer" "authorize" ;;
  esac
  # Shown once, the first time the account's key is created: store it before anything else.
  new_recovery=$(json_field "$answer" recovery_code)
  recovery_where=''
  if [ -n "$new_recovery" ]; then
    recovery_where=$(printf '%s' "$new_recovery" | secret_save "$RECOVERY_SERVICE" "$RC_ACCOUNT" "$RC_FILE" "BotChatter recovery code ($RC_ACCOUNT)")
  elif [ -n "$SOCIAL_CONNECT_RECOVERY_CODE" ]; then
    recovery_where=$(printf '%s' "$SOCIAL_CONNECT_RECOVERY_CODE" | secret_save "$RECOVERY_SERVICE" "$RC_ACCOUNT" "$RC_FILE" "BotChatter recovery code ($RC_ACCOUNT)")
  fi
  redirect_to=$(json_field "$answer" redirect_to)
  [ "$(query_param "$redirect_to" state)" = "$state" ] || die "authorize: the answer's state does not match this sign-up"
  grant=$(query_param "$redirect_to" code)
  [ -n "$grant" ] || die "authorize: the answer carried no authorization code ($(query_param "$redirect_to" error))"

  tokens=$(printf 'grant_type=authorization_code&code=%s&redirect_uri=%s&client_id=%s&code_verifier=%s&resource=%s' \
    "$grant" "$(form_escape "$REDIRECT_URI")" "$(form_escape "$client_id")" "$verifier" "$(form_escape "$MCP_URL")" |
    post_stdin "$WEB/oauth/token" application/x-www-form-urlencoded)
  [ "$(status_code)" = 200 ] || explain_error "$tokens" "token exchange"
  access=$(json_field "$tokens" access_token)
  refresh=$(json_field "$tokens" refresh_token)
  [ -n "$access" ] || die "token exchange returned no access_token"
  where=$(printf '%s %s %s' "$access" "${refresh:--}" "$client_id" | save_tokens)
  rm -f "$PENDING_FILE"
  printf '%s\n' "$email" >"$ACCOUNT_FILE"

  say "signed_in: $email on $WEB"
  say "token: stored in $where"
  if [ -n "$new_recovery" ]; then
    say "recovery_code: stored in $recovery_where (the server shows it only once; it is required to authorize this account again, so keep it and back it up; it is never printed)"
  elif [ -n "$recovery_where" ]; then
    say "recovery_code: stored in $recovery_where"
  fi
  say "next: agent-signup.sh connect   (gives you the link your human opens to connect Telegram)"
}

refresh_tokens() {
  [ -n "$REFRESH" ] && [ "$REFRESH" != - ] || return 1
  tokens=$(printf 'grant_type=refresh_token&refresh_token=%s&client_id=%s&resource=%s' \
    "$(form_escape "$REFRESH")" "$(form_escape "$CLIENT_ID")" "$(form_escape "$MCP_URL")" |
    post_stdin "$WEB/oauth/token" application/x-www-form-urlencoded)
  if [ "$(status_code)" != 200 ]; then
    REFRESH_ERROR=$(json_field "$tokens" error_description)
    return 1
  fi
  new_access=$(json_field "$tokens" access_token)
  [ -n "$new_access" ] || return 1
  new_refresh=$(json_field "$tokens" refresh_token)
  ACCESS=$new_access REFRESH=${new_refresh:-$REFRESH}
  printf '%s %s %s' "$ACCESS" "$REFRESH" "$CLIENT_ID" | save_tokens >/dev/null
}

# One JSON-RPC message to /mcp. Prints the response body (SSE "data:" lines unwrapped).
MCP_SESSION=
mcp_post() { # JSON
  : >"$TMP/headers"
  {
    printf 'Authorization: Bearer %s\n' "$ACCESS"
    [ -n "$MCP_SESSION" ] && printf 'Mcp-Session-Id: %s\n' "$MCP_SESSION"
  } | curl -sS --max-time 60 -H @- -H 'Content-Type: application/json' \
    -H 'Accept: application/json, text/event-stream' -H 'MCP-Protocol-Version: 2025-06-18' \
    -D "$TMP/headers" -o "$TMP/body" -w '%{http_code}' --data-binary "$1" "$MCP_URL" >"$TMP/status" ||
    die "cannot reach $MCP_URL"
  if grep -qi '^content-type:[[:space:]]*text/event-stream' "$TMP/headers"; then
    sed -n 's/^data:[[:space:]]*//p' "$TMP/body"
  else
    cat "$TMP/body"
  fi
}

mcp_session() {
  init='{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"botchatter-agent-signup","version":"0.1.0"}}}'
  mcp_post "$init" >/dev/null
  if [ "$(status_code)" = 401 ]; then
    REFRESH_ERROR=''
    if ! refresh_tokens; then
      case $REFRESH_ERROR in
        *'Encryption keys changed'*) die "Encryption keys changed; connect this assistant again: run signup and authorize again (the stored recovery code is sent automatically)" ;;
      esac
      die "the stored token for $WEB was refused and could not be refreshed${REFRESH_ERROR:+ ($REFRESH_ERROR)}: run signup and authorize again"
    fi
    mcp_post "$init" >/dev/null
  fi
  [ "$(status_code)" = 200 ] || die "MCP initialize failed (HTTP $(status_code))"
  MCP_SESSION=$(sed -n 's/^[Mm][Cc][Pp]-[Ss][Ee][Ss][Ss][Ii][Oo][Nn]-[Ii][Dd]:[[:space:]]*//p' "$TMP/headers" | tr -d '\r' | sed -n 1p)
  mcp_post '{"jsonrpc":"2.0","method":"notifications/initialized"}' >/dev/null
}

# Calls a tool; prints the JSON-RPC response. Exit 3 when the tool reports an error.
mcp_tool() { # NAME ARGUMENTS_JSON
  load_tokens
  args=${2:-}
  [ -n "$args" ] || args='{}'
  mcp_session
  out=$(mcp_post "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"$1\",\"arguments\":$args}}")
  [ "$(status_code)" = 200 ] || die "tools/call $1 failed (HTTP $(status_code))"
  printf '%s\n' "$out"
  case $out in *'"isError":true'*) return 3 ;; esac
  return 0
}

cmd_call() {
  [ $# -ge 1 ] || die "call: name a tool (for example catch_up, get_mentions, find_chats, read_recent_messages, draft_reply; all 23 are in skills/botchatter/references/mcp-tools.md)"
  case $1 in *[!a-z_]*) die "call: not a tool name: $1" ;; esac
  mcp_tool "$1" "${2:-}"
}

cmd_connect() {
  provider=telegram
  while [ $# -gt 0 ]; do
    case $1 in
      --provider) [ $# -ge 2 ] || die "--provider needs a value"; provider=$2; shift 2 ;;
      *) die "connect: unknown argument $1" ;;
    esac
  done
  case $provider in telegram | whatsapp) ;; *) die "connect: provider is telegram or whatsapp" ;; esac
  out=$(mcp_tool connect_account "{\"provider\":\"$provider\"}")
  rc=$?
  [ $rc -eq 3 ] && { printf '%s\n' "$out"; exit 3; }
  [ $rc -eq 0 ] || exit $rc
  # The tool's text is JSON inside a JSON string, so its quotes arrive escaped.
  url=$(printf '%s' "$out" | sed -n 's/.*connect_url\\":\\"\([^"\\]*\)\\".*/\1/p')
  [ -n "$url" ] || { printf '%s\n' "$out"; die "connect: no connect_url in the answer"; }
  say "connect_url: $url"
  say "expires_in: 30 minutes"
  say "next: give this link to your human only. They open it, then scan the QR code: Telegram > Settings > Devices > Link Desktop Device (or tap the tg:// link on their phone); WhatsApp (beta) > Settings > Linked devices > Link a device, with the link open on a computer or second screen, not the same phone. Then run: agent-signup.sh status"
}

cmd_where() {
  if secret_exists "$KEYCHAIN_SERVICE" "$HOST_KEY" "$TOKEN_FILE"; then
    if [ -f "$TOKEN_FILE" ]; then say "token: $TOKEN_FILE"
    else say "token: $(store_kind) (service $KEYCHAIN_SERVICE, account $HOST_KEY)"
    fi
  else
    say "token: none stored for $WEB"
  fi
  if [ -f "$ACCOUNT_FILE" ]; then
    email=$(sed -n 1p "$ACCOUNT_FILE")
    recovery_names "$email"
    say "account: $email"
    if secret_exists "$RECOVERY_SERVICE" "$RC_ACCOUNT" "$RC_FILE"; then
      if [ -f "$RC_FILE" ]; then say "recovery_code: $RC_FILE"
      else say "recovery_code: $(store_kind) (service $RECOVERY_SERVICE, account $RC_ACCOUNT)"
      fi
    else
      say "recovery_code: none stored for $email"
    fi
  fi
  [ -f "$PENDING_FILE" ] && say "pending_signup: $PENDING_FILE"
  return 0
}

cmd_host() {
  case ${1:-} in
    '')
      say "web: $WEB ($WEB_SOURCE)"
      say "mcp_url: $MCP_URL"
      return 0 ;;
    --reset)
      rm -f "$HOST_FILE"
      say "host: forgotten; $DEFAULT_WEB from now on"
      say "mcp_url: $DEFAULT_WEB/mcp"
      say "claude_code: printf '%s' '{\"mcp_url\":\"$DEFAULT_WEB/mcp\"}' | claude plugin configure botchatter@botchatter --values-stdin"
      return 0 ;;
    http://* | https://*) ;;
    *) die "host: pass a URL like https://botchatter.ai or http://localhost:8787, or --reset" ;;
  esac
  WEB=${1%/}
  meta=$(curl -fsS --max-time 20 "$WEB/.well-known/oauth-protected-resource/mcp") ||
    die "cannot reach $WEB/.well-known/oauth-protected-resource/mcp (is it a BotChatter host?)"
  MCP_URL=$(json_field "$meta" resource)
  [ -n "$MCP_URL" ] || die "$WEB did not name its MCP resource"
  mkdir -p "$CONFIG_DIR" && chmod 700 "$CONFIG_DIR"
  if [ "$WEB" = "$DEFAULT_WEB" ]; then
    rm -f "$HOST_FILE"
    say "host: $WEB (the default; nothing saved)"
  else
    printf '%s\n' "$WEB" >"$HOST_FILE"
    say "host: saved $WEB in $HOST_FILE"
  fi
  say "mcp_url: $MCP_URL"
  say "claude_code: printf '%s' '{\"mcp_url\":\"$MCP_URL\"}' | claude plugin configure botchatter@botchatter --values-stdin"
  say "codex: codex mcp add botchatter-custom --url $MCP_URL"
  [ -n "$SOCIAL_CONNECT_WEB" ] && [ "${SOCIAL_CONNECT_WEB%/}" != "$WEB" ] &&
    say "note: SOCIAL_CONNECT_WEB=$SOCIAL_CONNECT_WEB is set and still wins in this shell"
  return 0
}

case ${1:-} in
  describe) shift; cmd_describe "$@" ;;
  signup) shift; cmd_signup "$@" ;;
  authorize) shift; cmd_authorize "$@" ;;
  status) shift; mcp_tool connection_status '{}' ;;
  connect) shift; cmd_connect "$@" ;;
  call) shift; cmd_call "$@" ;;
  where) shift; cmd_where ;;
  logout) shift; forget_tokens; rm -f "$PENDING_FILE"; say "logged_out: $WEB (the recovery code is kept)" ;;
  host) shift; cmd_host "$@" ;;
  *)
    cat >&2 <<'USAGE'
usage: agent-signup.sh describe
       agent-signup.sh signup EMAIL [--agent-name NAME]
       agent-signup.sh authorize --code CODE          (--code - reads it from stdin)
       agent-signup.sh status
       agent-signup.sh connect [--provider telegram]
       agent-signup.sh call TOOL [JSON_ARGUMENTS]
       agent-signup.sh where
       agent-signup.sh logout
       agent-signup.sh host [URL | --reset]
USAGE
    exit 2 ;;
esac
