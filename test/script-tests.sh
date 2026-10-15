#!/bin/sh
# Offline checks: the manifests agree, the scripts lint, and the sign-up script's helpers behave.
# Needs jq and openssl; shellcheck when installed. Touches nothing outside a temporary directory.
set -eu
cd "$(dirname "$0")/.."
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
ok() { printf 'ok: %s\n' "$*"; }

for f in .claude-plugin/plugin.json .claude-plugin/marketplace.json .codex-plugin/plugin.json .mcp.json .codex-mcp.json package.json; do
  jq -e . "$f" >/dev/null || fail "$f is not valid JSON"
done
ok "JSON files parse"

default=https://staging.cooposio.com/mcp
# shellcheck disable=SC2016 # the literal placeholder Claude Code substitutes
[ "$(jq -r '.mcpServers["social-connect"].url' .mcp.json)" = '${user_config.mcp_url}' ] || fail ".mcp.json must use the mcp_url option"
[ "$(jq -r '.userConfig.mcp_url.default' .claude-plugin/plugin.json)" = "$default" ] || fail "mcp_url default"
[ "$(jq -r '.mcpServers' .codex-plugin/plugin.json)" = ./.codex-mcp.json ] || fail "codex manifest must point at .codex-mcp.json"
[ "$(jq -r '.mcpServers["social-connect"].url' .codex-mcp.json)" = "$default" ] || fail "codex MCP url must be literal"
for k in name version description license; do
  [ "$(jq -r ".$k" .claude-plugin/plugin.json)" = "$(jq -r ".$k" .codex-plugin/plugin.json)" ] || fail "manifests disagree on $k"
done
grep -q "DEFAULT_WEB=${default%/mcp}\$" scripts/agent-signup.sh || fail "agent-signup.sh default host"
grep -q "'${default%/mcp}'" scripts/agent-signup.ps1 || fail "agent-signup.ps1 default host"
ok "manifests agree"

if grep -rniE 'end-to-end encrypt|zero-knowledge' --include='*.md' . | grep -viE 'never|not |do not'; then
  fail "a forbidden privacy claim"
fi
ok "no forbidden privacy claims"

if command -v shellcheck >/dev/null 2>&1; then
  shellcheck -s sh scripts/agent-signup.sh test/script-tests.sh
  ok "shellcheck"
else
  printf 'skip: shellcheck not installed\n'
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export XDG_CONFIG_HOME="$tmp" SOCIAL_CONNECT_TOKEN_STORE=file SOCIAL_CONNECT_WEB=http://127.0.0.1:9
S=scripts/agent-signup.sh
rc=0; sh "$S" >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 2 ] || fail "no subcommand must print usage and exit 2"
sh "$S" host | grep -q '^mcp_url: http://127.0.0.1:9/mcp$' || fail "host shows the override"
sh "$S" where | grep -q 'none stored' || fail "where with nothing stored"
sh "$S" authorize --code abc 2>&1 | grep -q '6-digit' || fail "authorize rejects a non-numeric code"
sh "$S" authorize --code 123456 2>&1 | grep -q 'no sign-up in progress' || fail "authorize without signup"
sh "$S" signup not-an-email 2>&1 | grep -q 'own email' || fail "signup checks the address"
sh "$S" status 2>&1 | grep -q 'not signed in' || fail "status without a token"
ok "agent-signup.sh offline behaviour"

# PKCE: RFC 7636 appendix B vector.
challenge=$(printf '%s' dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk | openssl dgst -sha256 -binary | openssl base64 -A | tr '+/' '-_' | tr -d '=')
[ "$challenge" = E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM ] || fail "PKCE S256"
ok "PKCE S256"
