<#
  localclaude.ps1 — Claude Code をローカルの Ollama モデルで動かすラッパー（Windows ネイティブ版）

    - serve が落ちていれば ollama serve を起動（Windows）
    - Anthropic 互換 API を「ネイティブ → LiteLLM フォールバック」で自動判定
    - 終了時にモデルだけ offload（serve / bridge は残す）
    - claude の引数はそのまま透過（-- 区切り、または未知トークン以降を委譲）

  使い方:
    localclaude [-m|--model <name>] [-l|--list] [--keep] [--host <url>]
                [--bridge auto|native|litellm] [--ctx <n>] [-- <claude args...>]

  ※ macOS / Linux 版は bash の bin/localclaude を使用。
#>

# ── 設定（環境変数で上書き可）─────────────────────────────────
$DefaultModel = if ($env:LOCALCLAUDE_MODEL) { $env:LOCALCLAUDE_MODEL } else { 'qwen2.5-coder:32b' }
$DefaultHost  = if ($env:LOCALCLAUDE_HOST) { $env:LOCALCLAUDE_HOST } elseif ($env:OLLAMA_HOST) { $env:OLLAMA_HOST } else { 'localhost:11434' }
$LitellmPort  = if ($env:LOCALCLAUDE_LITELLM_PORT) { $env:LOCALCLAUDE_LITELLM_PORT } else { '4000' }
$LitellmUrl   = "http://localhost:$LitellmPort"
$KeepAlive    = '30m'
$ApiTimeoutMs = if ($env:LOCALCLAUDE_TIMEOUT_MS) { $env:LOCALCLAUDE_TIMEOUT_MS } else { '600000' }
$StateDir     = if ($env:LOCALCLAUDE_STATE) { $env:LOCALCLAUDE_STATE } else { Join-Path $env:LOCALAPPDATA 'localclaude' }

# ── 出力ヘルパ ────────────────────────────────────────────────
function Log($m)  { [Console]::Error.WriteLine("[localclaude] $m") }
function Warn($m) { [Console]::Error.WriteLine("[localclaude] warn: $m") }
function Die($m)  { [Console]::Error.WriteLine("[localclaude] error: $m"); exit 1 }

function Show-Usage {
  @'
localclaude — Claude Code をローカルの Ollama モデルで動かすラッパー（Windows）

使い方:
  localclaude [-m|--model <name>] [-l|--list] [--keep] [--host <url>]
              [--bridge auto|native|litellm] [--ctx <n>] [-- <claude args...>]

オプション:
  -m, --model <name>   使う Ollama モデル（既定: $env:LOCALCLAUDE_MODEL or qwen2.5-coder:32b）
  -l, --list           ollama list を表示して終了
      --keep           終了時にモデルを offload しない
      --bridge <mode>  auto(既定) | native | litellm
      --ctx <n>        指定時のみ <model>-ctx<n> 派生を作成（既定: そのまま使用）
      --host <url>     接続先 Ollama（既定 localhost:11434 / 環境変数 LOCALCLAUDE_HOST でも可）
  -h, --help           このヘルプ
  -- <args...>         以降を素の claude にそのまま渡す
'@ | ForEach-Object { [Console]::Error.WriteLine($_) }
}

# ── 引数パース（-- / 未知トークン以降は claude へ委譲）──────────
$Model = $DefaultModel; $ModelExplicit = $false
$BridgeMode = 'auto'; $HostArg = ''
$DoList = $false; $Keep = $false
$NumCtx = $env:LOCALCLAUDE_CTX
$ClaudeArgs = @()

$i = 0; $n = $args.Count
while ($i -lt $n) {
  $a = [string]$args[$i]
  if     ($a -eq '-m' -or $a -eq '--model') { $i++; if ($i -ge $n) { Die '--model にモデル名が必要です' }; $Model = [string]$args[$i]; $ModelExplicit = $true }
  elseif ($a -like '--model=*')  { $Model = $a.Substring(8); $ModelExplicit = $true }
  elseif ($a -eq '-l' -or $a -eq '--list') { $DoList = $true }
  elseif ($a -eq '--keep')       { $Keep = $true }
  elseif ($a -eq '--bridge')     { $i++; if ($i -ge $n) { Die '--bridge に値が必要です' }; $BridgeMode = [string]$args[$i] }
  elseif ($a -like '--bridge=*') { $BridgeMode = $a.Substring(9) }
  elseif ($a -eq '--ctx')        { $i++; if ($i -ge $n) { Die '--ctx に数値が必要です' }; $NumCtx = [string]$args[$i] }
  elseif ($a -like '--ctx=*')    { $NumCtx = $a.Substring(6) }
  elseif ($a -eq '--host')       { $i++; if ($i -ge $n) { Die '--host に値が必要です' }; $HostArg = [string]$args[$i] }
  elseif ($a -like '--host=*')   { $HostArg = $a.Substring(7) }
  elseif ($a -eq '-h' -or $a -eq '--help') { Show-Usage; exit 0 }
  elseif ($a -eq '--')           { $i++; while ($i -lt $n) { $ClaudeArgs += [string]$args[$i]; $i++ }; break }
  else                           { while ($i -lt $n) { $ClaudeArgs += [string]$args[$i]; $i++ }; break }
  $i++
}

if ($BridgeMode -notin @('auto','native','litellm')) { Die "--bridge は auto|native|litellm のいずれか（指定: $BridgeMode）" }

# ── 接続先 Ollama を解決 ──────────────────────────────────────
$rawHost = if ($HostArg) { $HostArg } else { $DefaultHost }
$rawHost = $rawHost.TrimEnd('/')
if     ($rawHost -like 'http://*')  { $scheme = 'http';  $hp = $rawHost.Substring(7) }
elseif ($rawHost -like 'https://*') { $scheme = 'https'; $hp = $rawHost.Substring(8) }
else                                { $scheme = 'http';  $hp = $rawHost }
if ($hp -notmatch ':') { $hp = "${hp}:11434" }
$OllamaUrl = "${scheme}://${hp}"
$env:OLLAMA_HOST = $hp                              # ollama CLI もこのホストへ
$IsLocal = $hp -match '^(localhost|127\.0\.0\.1|0\.0\.0\.0|\[::1\]):'

# ── 前提チェック ──────────────────────────────────────────────
if (-not (Get-Command ollama -ErrorAction SilentlyContinue)) { Die 'ollama 未インストール: https://ollama.com/download/windows' }

function Test-OllamaUp {
  try { Invoke-RestMethod -Uri "$OllamaUrl/api/tags" -TimeoutSec 3 -ErrorAction Stop | Out-Null; return $true }
  catch { return $false }
}

function Ensure-OllamaServe {
  if (Test-OllamaUp) { return }
  if (-not $IsLocal) { Die "リモート Ollama ($OllamaUrl) に接続できません。サーバ側で ollama を起動してください" }
  Log 'ollama serve が応答しません。起動します…'
  try { Start-Process -FilePath 'ollama' -ArgumentList 'serve' -WindowStyle Hidden | Out-Null } catch { Warn "ollama serve の起動に失敗: $_" }
  for ($k = 0; $k -lt 30; $k++) { if (Test-OllamaUp) { Log 'ollama serve 起動完了'; return }; Start-Sleep -Milliseconds 500 }
  Die 'ollama serve を起動できませんでした'
}

function Get-ModelNames {
  ,@(ollama list 2>$null | Select-Object -Skip 1 | ForEach-Object { ($_ -split '\s+')[0] } | Where-Object { $_ })
}

function Test-ModelExists($name) { (Get-ModelNames) -contains $name }

function Select-Model {
  Ensure-OllamaServe
  $models = Get-ModelNames
  if ($models.Count -eq 0) {
    Warn "インストール済みモデルがありません → 既定 $DefaultModel を使用（無ければ pull します）"
    $script:Model = $DefaultModel; return
  }
  [Console]::Error.WriteLine('使用するモデルを選択してください:')
  for ($j = 0; $j -lt $models.Count; $j++) { [Console]::Error.WriteLine(("  {0}) {1}" -f ($j + 1), $models[$j])) }
  $sel = Read-Host "番号を入力 [1-$($models.Count)] (Enter=1)"
  if (-not $sel) { $sel = '1' }
  if ($sel -match '^[0-9]+$' -and [int]$sel -ge 1 -and [int]$sel -le $models.Count) {
    $script:Model = $models[[int]$sel - 1]; Log "選択: $script:Model"
  } else { Die "無効な選択: $sel" }
}

# ── --list ────────────────────────────────────────────────────
if ($DoList) { Ensure-OllamaServe; ollama list; exit 0 }

# ── --model 省略時はモデル選択（対話時のみ）────────────────────
if (-not $ModelExplicit) {
  if ([Environment]::UserInteractive -and -not [Console]::IsInputRedirected) { Select-Model }
  else { Warn "--model 未指定かつ非対話 → 既定 $DefaultModel を使用"; $Model = $DefaultModel }
}

# ── モデル準備（必要なら pull、--ctx 指定時のみ派生 create）──────
function Prepare-Model {
  Ensure-OllamaServe
  $base = $Model
  if (-not $NumCtx -or $NumCtx -eq '0') {
    $script:RunModel = $base
    if (-not (Test-ModelExists $base)) { Log "モデル取得: ollama pull $base"; ollama pull $base; if ($LASTEXITCODE -ne 0) { Die "pull 失敗: $base" } }
    return
  }
  $script:RunModel = "$base-ctx$NumCtx"
  if (Test-ModelExists $script:RunModel) { return }
  if (-not (Test-ModelExists $base)) { Log "ベースモデル取得: ollama pull $base"; ollama pull $base; if ($LASTEXITCODE -ne 0) { Die "pull 失敗: $base" } }
  Log "context長 $NumCtx を焼き込んだ派生モデルを作成: $script:RunModel"
  New-Item -ItemType Directory -Force -Path $StateDir | Out-Null
  $safe = ($script:RunModel -replace '[:/\\]', '_')
  $mf = Join-Path $StateDir "Modelfile.$safe"
  "FROM $base`nPARAMETER num_ctx $NumCtx" | Set-Content -Path $mf -Encoding ascii
  ollama create $script:RunModel -f $mf
  if ($LASTEXITCODE -ne 0) { Die "ollama create 失敗: $script:RunModel" }
}

# ── ブリッジ判定 ──────────────────────────────────────────────
function Test-NativeAnthropic {
  $body = @{ model = $script:RunModel; max_tokens = 8; messages = @(@{ role = 'user'; content = 'ping' }) } | ConvertTo-Json -Depth 6 -Compress
  try {
    $r = Invoke-WebRequest -Uri "$OllamaUrl/v1/messages" -Method Post -ContentType 'application/json' `
      -Headers @{ 'anthropic-version' = '2023-06-01' } -Body $body -TimeoutSec 20 -UseBasicParsing -ErrorAction Stop
    return ([int]$r.StatusCode -eq 200)
  } catch { return $false }
}

function Test-LitellmUp {
  try { Invoke-RestMethod -Uri "$LitellmUrl/v1/models" -TimeoutSec 3 -ErrorAction Stop | Out-Null; return $true } catch { return $false }
}

function Start-Litellm {
  if (-not (Get-Command litellm -ErrorAction SilentlyContinue)) { Die "litellm 未インストール（fallback に必要）。'uv tool install litellm[proxy]' 等で導入を" }
  if (Test-LitellmUp) {
    try {
      $models = Invoke-RestMethod -Uri "$LitellmUrl/v1/models" -TimeoutSec 3 -ErrorAction Stop
      if (($models | ConvertTo-Json -Depth 6) -match [regex]::Escape($script:RunModel)) { Log "LiteLLM は既に :$LitellmPort で稼働中（$script:RunModel）"; return }
    } catch {}
    Warn "既存 LiteLLM が別モデル設定 → 停止して $script:RunModel 用に再起動します"
    try { Get-NetTCPConnection -LocalPort ([int]$LitellmPort) -State Listen -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.OwningProcess -Force -ErrorAction SilentlyContinue } } catch {}
    Start-Sleep -Seconds 1
  }
  New-Item -ItemType Directory -Force -Path $StateDir | Out-Null
  $cfg = Join-Path $StateDir 'litellm.config.yaml'
  @"
model_list:
  - model_name: $script:RunModel
    litellm_params:
      model: ollama_chat/$script:RunModel
      api_base: $OllamaUrl
litellm_settings:
  drop_params: true
"@ | Set-Content -Path $cfg -Encoding ascii
  Log "LiteLLM ブリッジを起動 (:$LitellmPort)…"
  $log = Join-Path $StateDir 'litellm.log'
  try { Start-Process -FilePath 'litellm' -ArgumentList @('--config', $cfg, '--port', "$LitellmPort") -WindowStyle Hidden -RedirectStandardOutput $log -ErrorAction Stop | Out-Null }
  catch { Die "LiteLLM の起動に失敗: $_" }
  for ($k = 0; $k -lt 40; $k++) { if (Test-LitellmUp) { Log 'LiteLLM 起動完了'; return }; Start-Sleep -Milliseconds 500 }
  Die "LiteLLM を起動できませんでした（$log を確認）"
}

function Resolve-Bridge {
  switch ($BridgeMode) {
    'native'  { $script:AnthropicBaseUrl = $OllamaUrl; Log 'bridge=native (強制)' }
    'litellm' { Start-Litellm; $script:AnthropicBaseUrl = $LitellmUrl; Log 'bridge=litellm (強制)' }
    default {
      if (Test-NativeAnthropic) { $script:AnthropicBaseUrl = $OllamaUrl; Log 'bridge=native（Ollama が Anthropic 互換を提供）' }
      else { Warn 'Ollama ネイティブの Anthropic 互換が確認できず → LiteLLM にフォールバック'; Start-Litellm; $script:AnthropicBaseUrl = $LitellmUrl; Log 'bridge=litellm' }
    }
  }
}

function Warm-Model {
  Log "モデルを warm ロード: $script:RunModel"
  try { Invoke-RestMethod -Uri "$OllamaUrl/api/generate" -Method Post -TimeoutSec 120 -ContentType 'application/json' `
      -Body (@{ model = $script:RunModel; keep_alive = $KeepAlive } | ConvertTo-Json) -ErrorAction Stop | Out-Null }
  catch { Warn 'warm ロードに失敗（claude 起動後にロードされます）' }
}

function Invoke-Cleanup {
  if ($Keep) { Log "--keep 指定: モデルは offload しません（$script:RunModel）"; return }
  Log "モデルを offload: $script:RunModel"
  ollama stop $script:RunModel 2>$null
  if ($LASTEXITCODE -ne 0) {
    try { Invoke-RestMethod -Uri "$OllamaUrl/api/generate" -Method Post -TimeoutSec 10 -ContentType 'application/json' -Body (@{ model = $script:RunModel; keep_alive = 0 } | ConvertTo-Json) -ErrorAction Stop | Out-Null } catch {}
  }
}

# ── 実行 ──────────────────────────────────────────────────────
if (-not (Get-Command claude -ErrorAction SilentlyContinue)) { Die 'claude（Claude Code）が見つかりません: https://claude.com/claude-code' }

Prepare-Model
Resolve-Bridge
Warm-Model

Log "Claude Code を起動 — model=$script:RunModel / base=$script:AnthropicBaseUrl"
Log "（終了すると $script:RunModel を offload します）"

# env はこのプロセス（と子の claude）にだけ注入
$env:ANTHROPIC_BASE_URL = $script:AnthropicBaseUrl
$env:ANTHROPIC_AUTH_TOKEN = 'ollama'
$env:ANTHROPIC_API_KEY = ''
$env:ANTHROPIC_MODEL = $script:RunModel
$env:ANTHROPIC_SMALL_FAST_MODEL = $script:RunModel
$env:ANTHROPIC_DEFAULT_HAIKU_MODEL = $script:RunModel
$env:ANTHROPIC_DEFAULT_SONNET_MODEL = $script:RunModel
$env:ANTHROPIC_DEFAULT_OPUS_MODEL = $script:RunModel
$env:API_TIMEOUT_MS = $ApiTimeoutMs
$env:CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC = '1'

try {
  if ($ClaudeArgs.Count -gt 0) { & claude @ClaudeArgs } else { & claude }
} finally {
  Invoke-Cleanup
}
