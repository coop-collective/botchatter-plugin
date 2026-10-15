<#
Social Connect agent sign-up for Windows (PowerShell 5.1 or 7). The same commands and output as
agent-signup.sh (which Git for Windows' bash and WSL also run):

  agent-signup.ps1 describe
  agent-signup.ps1 signup EMAIL [-AgentName NAME]
  agent-signup.ps1 authorize -Code CODE            (-Code - reads it from stdin)
  agent-signup.ps1 status
  agent-signup.ps1 connect [-Provider telegram]
  agent-signup.ps1 call TOOL [JSON_ARGUMENTS]
  agent-signup.ps1 where
  agent-signup.ps1 logout
  agent-signup.ps1 host [URL | -Reset]

An autonomous agent with its own mailbox creates and owns a Social Connect account without a
browser, then hands its human a link to connect Telegram. Secrets (the emailed code, the PKCE
verifier, access and refresh tokens) are never printed. On Windows the tokens are kept in a file
encrypted for the current Windows user (DPAPI) under %APPDATA%\social-connect; elsewhere in a
mode-600 file, and the script says where. Settings: SOCIAL_CONNECT_WEB (else the host saved with
`host URL`, else https://staging.cooposio.com), as for the sh script.
#>
param(
  [Parameter(Position = 0)][string]$Command = '',
  [Parameter(Position = 1)][string]$Arg1 = '',
  [Parameter(Position = 2)][string]$Arg2 = '',
  [string]$AgentName = '',
  [string]$Email = '',
  [string]$Code = '',
  [string]$Provider = 'telegram',
  [switch]$Reset
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Net.Http

$DefaultWeb = 'https://staging.cooposio.com'
$RedirectUri = 'http://127.0.0.1:8976/callback'
$ConfigRoot = if ($env:XDG_CONFIG_HOME) { $env:XDG_CONFIG_HOME } elseif ($env:APPDATA) { $env:APPDATA } else { Join-Path $HOME '.config' }
$ConfigDir = Join-Path $ConfigRoot 'social-connect'
$HostFile = Join-Path $ConfigDir 'host'
$IsWin = [System.Environment]::OSVersion.Platform -eq 'Win32NT'

$SavedHost = if (Test-Path $HostFile) { ([string](Get-Content $HostFile -TotalCount 1)).Trim() } else { '' }
if ($env:SOCIAL_CONNECT_WEB) { $Web = $env:SOCIAL_CONNECT_WEB; $WebSource = 'SOCIAL_CONNECT_WEB' }
elseif ($SavedHost) { $Web = $SavedHost; $WebSource = "saved in $HostFile" }
else { $Web = $DefaultWeb; $WebSource = 'default' }
$Web = $Web.TrimEnd('/')

function Say([string]$Text) { Write-Output $Text }
function Fail([string]$Text) { [Console]::Error.WriteLine("social-connect: $Text"); exit 1 }

function Set-Host([string]$Url) {
  $script:Web = $Url.TrimEnd('/')
  $script:McpUrl = "$($script:Web)/mcp"
  $script:HostKey = ($script:Web -replace '^[a-z]+://', '') -replace '[^A-Za-z0-9.-]', '_'
  $script:PendingFile = Join-Path $ConfigDir "pending-$($script:HostKey)"
  $script:TokenFile = Join-Path $ConfigDir "token-$($script:HostKey)"
}
Set-Host $Web

$Http = New-Object System.Net.Http.HttpClient
$Http.Timeout = [TimeSpan]::FromSeconds(60)

# One HTTP request; never throws on an HTTP status. Returns @{ Status; Body; Headers }.
function Send([string]$Method, [string]$Url, [string]$Body = $null, [string]$ContentType = 'application/json', [hashtable]$Headers = @{}) {
  $req = [System.Net.Http.HttpRequestMessage]::new([System.Net.Http.HttpMethod]::new($Method), $Url)
  $req.Headers.TryAddWithoutValidation('Accept', 'application/json, text/event-stream') | Out-Null
  foreach ($k in $Headers.Keys) { $req.Headers.TryAddWithoutValidation($k, [string]$Headers[$k]) | Out-Null }
  if ($null -ne $Body) { $req.Content = [System.Net.Http.StringContent]::new($Body, [System.Text.Encoding]::UTF8, $ContentType) }
  try { $res = $Http.SendAsync($req).GetAwaiter().GetResult() } catch { Fail "cannot reach $Url" }
  $text = $res.Content.ReadAsStringAsync().GetAwaiter().GetResult()
  $type = if ($res.Content.Headers.ContentType) { $res.Content.Headers.ContentType.MediaType } else { '' }
  if ($type -eq 'text/event-stream') {
    $text = (($text -split "`n") | Where-Object { $_ -match '^data:' } | ForEach-Object { ($_ -replace '^data:\s*', '').TrimEnd("`r") }) -join "`n"
  }
  $session = $null
  $values = $null
  if ($res.Headers.TryGetValues('Mcp-Session-Id', [ref]$values)) { $session = @($values)[0] }
  return @{ Status = [int]$res.StatusCode; Body = $text; Session = $session }
}

function Parse([string]$Text) { try { return $Text | ConvertFrom-Json } catch { return $null } }

function Explain($Res, [string]$Context) {
  $j = Parse $Res.Body
  $detail = ''
  if ($j -and $j.error) { $detail = ": $($j.error)" }
  if ($j -and $j.error_description) { $detail += " - $($j.error_description)" }
  Fail "$Context failed (HTTP $($Res.Status))$detail"
}

function Form([hashtable]$Fields) {
  ($Fields.Keys | ForEach-Object { "$_=$([Uri]::EscapeDataString([string]$Fields[$_]))" }) -join '&'
}

function B64Url([byte[]]$Bytes) { [Convert]::ToBase64String($Bytes).TrimEnd('=').Replace('+', '-').Replace('/', '_') }

function Ensure-ConfigDir {
  if (-not (Test-Path $ConfigDir)) { New-Item -ItemType Directory -Force -Path $ConfigDir | Out-Null }
  if (-not $IsWin) { & chmod 700 $ConfigDir 2>$null }
}

function Write-Private([string]$Path, [string]$Text) {
  Ensure-ConfigDir
  if (-not $IsWin) { New-Item -ItemType File -Force -Path $Path | Out-Null; & chmod 600 $Path 2>$null }
  Set-Content -Path $Path -Value $Text -NoNewline
}

# --- token storage ----------------------------------------------------------------------------

function Save-Tokens([string]$Access, [string]$Refresh, [string]$ClientId) {
  $value = "$Access $Refresh $ClientId"
  if ($IsWin) {
    $secure = ConvertTo-SecureString $value -AsPlainText -Force
    Write-Private $TokenFile (ConvertFrom-SecureString $secure)
    return "$TokenFile (encrypted for this Windows user with DPAPI)"
  }
  Write-Private $TokenFile $value
  return "$TokenFile (mode 600; on macOS and Linux agent-signup.sh uses the OS keychain)"
}

function Load-Tokens {
  if (-not (Test-Path $TokenFile)) { Fail "not signed in to ${Web}: run signup, then authorize (or set SOCIAL_CONNECT_WEB)" }
  $raw = ([string](Get-Content $TokenFile -TotalCount 1)).Trim()
  if ($IsWin) {
    try {
      $secure = ConvertTo-SecureString $raw
      $raw = [System.Net.NetworkCredential]::new('', $secure).Password
    } catch { Fail "the stored token for $Web is unreadable: run logout, then signup again" }
  }
  $parts = $raw -split ' '
  if (-not $parts[0]) { Fail "the stored token for $Web is unreadable: run logout, then signup again" }
  $script:Access = $parts[0]; $script:Refresh = $parts[1]; $script:ClientId = $parts[2]
}

# --- commands ---------------------------------------------------------------------------------

function Cmd-Describe {
  $res = Send 'GET' "$Web/api/agent/"
  if ($res.Status -ne 200) { Fail "$Web does not offer agent sign-up (GET /api/agent/ answered HTTP $($res.Status))" }
  Say $res.Body
}

function Cmd-Signup([string]$Address) {
  if ($Address -notmatch '^[^@\s"\\]+@[^@\s"\\]+\.[^@\s"\\]+$') { Fail 'signup: pass the agent''s own email address' }
  $clientName = if ($AgentName) { $AgentName } else { 'Social Connect agent' }
  $reg = Send 'POST' "$Web/oauth/register" (@{
      client_name = $clientName; redirect_uris = @($RedirectUri); grant_types = @('authorization_code', 'refresh_token')
      response_types = @('code'); token_endpoint_auth_method = 'none'
    } | ConvertTo-Json -Compress)
  if ($reg.Status -ne 200 -and $reg.Status -ne 201) { Explain $reg 'client registration' }
  $clientId = (Parse $reg.Body).client_id
  if (-not $clientId) { Fail 'client registration returned no client_id' }

  $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
  $bytes = New-Object byte[] 32; $rng.GetBytes($bytes); $verifier = B64Url $bytes
  $sha = [System.Security.Cryptography.SHA256]::Create()
  $challenge = B64Url ($sha.ComputeHash([System.Text.Encoding]::ASCII.GetBytes($verifier)))
  $sbytes = New-Object byte[] 16; $rng.GetBytes($sbytes); $state = ($sbytes | ForEach-Object { $_.ToString('x2') }) -join ''
  $query = "response_type=code&client_id=$([Uri]::EscapeDataString($clientId))&redirect_uri=$([Uri]::EscapeDataString($RedirectUri))&scope=telegram&state=$state&code_challenge=$challenge&code_challenge_method=S256&resource=$([Uri]::EscapeDataString($McpUrl))&login_hint=$([Uri]::EscapeDataString($Address))"
  $authorizeUrl = "$Web/authorize?$query"

  $sent = Send 'POST' "$Web/api/agent/signup" (@{ email = $Address; agent_name = $AgentName } | ConvertTo-Json -Compress)
  switch ($sent.Status) {
    200 { }
    409 { Fail "$Address belongs to an account a person created in a browser: sign in through MCP OAuth (/mcp) instead" }
    429 { Explain $sent 'signup (rate-limited; wait the time it states, then retry)' }
    default { Explain $sent 'signup' }
  }
  $pending = [ordered]@{ email = $Address; agent_name = $AgentName; client_id = $clientId; verifier = $verifier; state = $state; authorize_url = $authorizeUrl }
  Write-Private $PendingFile ($pending | ConvertTo-Json -Compress)
  Say "web: $Web ($WebSource)"
  Say "code_sent: $Address (expires in $((Parse $sent.Body).expires_in_seconds) seconds)"
  Say 'next: read the 6-digit code from that mailbox, then run: agent-signup.ps1 authorize -Code <code>'
}

function Query-Param([string]$Url, [string]$Name) {
  $q = ($Url -split '\?', 2)[1]
  foreach ($pair in ($q -split '&')) {
    $kv = $pair -split '=', 2
    if ($kv[0] -eq $Name) { return [Uri]::UnescapeDataString($kv[1].Replace('+', ' ')) }
  }
  return ''
}

function Cmd-Authorize {
  $c = $Code
  if ($c -eq '-') { $c = [Console]::In.ReadLine() }
  $c = ([string]$c).Trim()
  if ($c -notmatch '^[0-9]+$') { Fail 'authorize: -Code takes the 6-digit code from the email' }
  if (-not (Test-Path $PendingFile)) { Fail "no sign-up in progress for ${Web}: run signup EMAIL first" }
  $p = Get-Content $PendingFile -Raw | ConvertFrom-Json

  $answer = Send 'POST' "$Web/api/agent/authorize" (@{ email = $p.email; code = $c; authorize_url = $p.authorize_url; agent_name = $p.agent_name } | ConvertTo-Json -Compress)
  if ($answer.Status -eq 400) { Explain $answer 'authorize (a wrong or expired code: run signup again for a new one)' }
  if ($answer.Status -ne 200) { Explain $answer 'authorize' }
  $redirectTo = (Parse $answer.Body).redirect_to
  if ((Query-Param $redirectTo 'state') -ne $p.state) { Fail "authorize: the answer's state does not match this sign-up" }
  $grant = Query-Param $redirectTo 'code'
  if (-not $grant) { Fail "authorize: the answer carried no authorization code ($(Query-Param $redirectTo 'error'))" }

  $tokens = Send 'POST' "$Web/oauth/token" (Form @{ grant_type = 'authorization_code'; code = $grant; redirect_uri = $RedirectUri; client_id = $p.client_id; code_verifier = $p.verifier; resource = $McpUrl }) 'application/x-www-form-urlencoded'
  if ($tokens.Status -ne 200) { Explain $tokens 'token exchange' }
  $t = Parse $tokens.Body
  if (-not $t.access_token) { Fail 'token exchange returned no access_token' }
  $refresh = if ($t.refresh_token) { $t.refresh_token } else { '-' }
  $where = Save-Tokens $t.access_token $refresh $p.client_id
  Remove-Item -Force $PendingFile
  Say "signed_in: $($p.email) on $Web"
  Say "token: stored in $where"
  Say 'next: agent-signup.ps1 connect   (gives you the link your human opens to connect Telegram)'
}

function Refresh-Tokens {
  if (-not $script:Refresh -or $script:Refresh -eq '-') { return $false }
  $res = Send 'POST' "$Web/oauth/token" (Form @{ grant_type = 'refresh_token'; refresh_token = $script:Refresh; client_id = $script:ClientId; resource = $McpUrl }) 'application/x-www-form-urlencoded'
  if ($res.Status -ne 200) { return $false }
  $t = Parse $res.Body
  if (-not $t.access_token) { return $false }
  $script:Access = $t.access_token
  if ($t.refresh_token) { $script:Refresh = $t.refresh_token }
  Save-Tokens $script:Access $script:Refresh $script:ClientId | Out-Null
  return $true
}

function Mcp([string]$Json) {
  $h = @{ Authorization = "Bearer $($script:Access)"; 'MCP-Protocol-Version' = '2025-06-18' }
  if ($script:McpSession) { $h['Mcp-Session-Id'] = $script:McpSession }
  return Send 'POST' $McpUrl $Json 'application/json' $h
}

# Calls a tool; prints the JSON-RPC response. Exit 3 when the tool reports an error.
function Invoke-Tool([string]$Name, [string]$ArgsJson) {
  if (-not $ArgsJson) { $ArgsJson = '{}' }
  Load-Tokens
  $script:McpSession = $null
  $init = '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"social-connect-agent-signup","version":"0.1.0"}}}'
  $res = Mcp $init
  if ($res.Status -eq 401) {
    if (-not (Refresh-Tokens)) { Fail "the stored token for $Web was refused and could not be refreshed: run signup and authorize again" }
    $res = Mcp $init
  }
  if ($res.Status -ne 200) { Fail "MCP initialize failed (HTTP $($res.Status))" }
  $script:McpSession = $res.Session
  Mcp '{"jsonrpc":"2.0","method":"notifications/initialized"}' | Out-Null
  $out = Mcp "{`"jsonrpc`":`"2.0`",`"id`":2,`"method`":`"tools/call`",`"params`":{`"name`":`"$Name`",`"arguments`":$ArgsJson}}"
  if ($out.Status -ne 200) { Fail "tools/call $Name failed (HTTP $($out.Status))" }
  return $out.Body
}

function Cmd-Connect {
  if ($Provider -notin @('telegram', 'whatsapp')) { Fail 'connect: provider is telegram or whatsapp' }
  $out = Invoke-Tool 'connect_account' "{`"provider`":`"$Provider`"}"
  $r = Parse $out
  if ($r.result.isError) { Say $out; exit 3 }
  $inner = Parse $r.result.content[0].text
  if (-not $inner.connect_url) { Say $out; Fail 'connect: no connect_url in the answer' }
  Say "connect_url: $($inner.connect_url)"
  Say 'expires_in: 30 minutes'
  Say 'next: give this link to your human only. They open it, then scan the QR code with Telegram (Settings > Devices > Link Desktop Device) or tap the tg:// link on their phone. Then run: agent-signup.ps1 status'
}

function Cmd-Call([string]$Tool, [string]$ArgsJson) {
  if (-not $Tool) { Fail 'call: name a tool (connection_status, connect_account, list_recent_chats, read_recent_messages, request_reply_approval)' }
  if ($Tool -notmatch '^[a-z_]+$') { Fail "call: not a tool name: $Tool" }
  $out = Invoke-Tool $Tool $ArgsJson
  Say $out
  if ((Parse $out).result.isError) { exit 3 }
}

function Cmd-Host([string]$Url) {
  if ($Reset) {
    Remove-Item -Force -ErrorAction SilentlyContinue $HostFile
    Say "host: forgotten; $DefaultWeb from now on"
    Say "mcp_url: $DefaultWeb/mcp"
    Say "claude_code: printf '%s' '{`"mcp_url`":`"$DefaultWeb/mcp`"}' | claude plugin configure social-connect@social-connect --values-stdin"
    return
  }
  if (-not $Url) { Say "web: $Web ($WebSource)"; Say "mcp_url: $McpUrl"; return }
  if ($Url -notmatch '^https?://') { Fail 'host: pass a URL like https://staging.cooposio.com or http://localhost:8787, or -Reset' }
  Set-Host $Url
  $meta = Send 'GET' "$Web/.well-known/oauth-protected-resource/mcp"
  $resource = if ($meta.Status -eq 200) { (Parse $meta.Body).resource } else { $null }
  if (-not $resource) { Fail "cannot reach $Web/.well-known/oauth-protected-resource/mcp (is it a Social Connect host?)" }
  Ensure-ConfigDir
  if ($Web -eq $DefaultWeb) {
    Remove-Item -Force -ErrorAction SilentlyContinue $HostFile
    Say "host: $Web (the default; nothing saved)"
  } else {
    Set-Content -Path $HostFile -Value $Web
    Say "host: saved $Web in $HostFile"
  }
  Say "mcp_url: $resource"
  Say "claude_code: printf '%s' '{`"mcp_url`":`"$resource`"}' | claude plugin configure social-connect@social-connect --values-stdin"
  Say "codex: codex mcp add social-connect-custom --url $resource"
  if ($env:SOCIAL_CONNECT_WEB -and $env:SOCIAL_CONNECT_WEB.TrimEnd('/') -ne $Web) { Say "note: SOCIAL_CONNECT_WEB=$($env:SOCIAL_CONNECT_WEB) is set and still wins in this shell" }
}

switch ($Command) {
  'describe' { Cmd-Describe }
  'signup' { Cmd-Signup $(if ($Email) { $Email } else { $Arg1 }) }
  'authorize' { Cmd-Authorize }
  'status' { $out = Invoke-Tool 'connection_status' '{}'; Say $out }
  'connect' { Cmd-Connect }
  'call' { Cmd-Call $Arg1 $Arg2 }
  'where' {
    if (Test-Path $TokenFile) { Say "token: $TokenFile" } else { Say "token: none stored for $Web" }
    if (Test-Path $PendingFile) { Say "pending_signup: $PendingFile" }
  }
  'logout' {
    Remove-Item -Force -ErrorAction SilentlyContinue $TokenFile, $PendingFile
    Say "logged_out: $Web"
  }
  'host' { Cmd-Host $Arg1 }
  default {
    [Console]::Error.WriteLine(@'
usage: agent-signup.ps1 describe
       agent-signup.ps1 signup EMAIL [-AgentName NAME]
       agent-signup.ps1 authorize -Code CODE          (-Code - reads it from stdin)
       agent-signup.ps1 status
       agent-signup.ps1 connect [-Provider telegram]
       agent-signup.ps1 call TOOL [JSON_ARGUMENTS]
       agent-signup.ps1 where
       agent-signup.ps1 logout
       agent-signup.ps1 host [URL | -Reset]
'@)
    exit 2
  }
}
