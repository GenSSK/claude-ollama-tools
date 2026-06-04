<#
  claude-ollama-tools installer (Windows / PowerShell)

    powershell -ExecutionPolicy Bypass -File .\install.ps1 [-BinDir <dir>] [-Copy]

      -BinDir <dir>   インストール先（既定: %USERPROFILE%\.local\bin）
      -Copy           リポジトリ参照でなくコピーして配置（既定: リポジトリ参照のシム）

  localclaude.cmd / ollama-manager.cmd を BinDir に作成し、ユーザー PATH に BinDir を追加します。
  macOS / Linux は install.sh を使用。
#>
param(
  [string]$BinDir = (Join-Path $env:USERPROFILE '.local\bin'),
  [switch]$Copy
)
$ErrorActionPreference = 'Stop'
function Log($m)  { Write-Host "[install] $m" }
function Warn($m) { Write-Warning $m }

$RepoDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$lcSrc = Join-Path $RepoDir 'bin\localclaude.ps1'
$omSrc = Join-Path $RepoDir 'bin\ollama-manager'
if (-not (Test-Path $lcSrc)) { throw "localclaude.ps1 が見つかりません: $lcSrc（リポジトリ内で実行してください）" }

New-Item -ItemType Directory -Force -Path $BinDir | Out-Null

if ($Copy) {
  Copy-Item $lcSrc (Join-Path $BinDir 'localclaude.ps1') -Force
  Copy-Item $omSrc (Join-Path $BinDir 'ollama-manager') -Force
  $lcTarget = Join-Path $BinDir 'localclaude.ps1'
  $omTarget = Join-Path $BinDir 'ollama-manager'
  Log "コピー: localclaude.ps1, ollama-manager → $BinDir"
} else {
  $lcTarget = $lcSrc
  $omTarget = $omSrc
}

# .cmd シム（cmd.exe / PowerShell どちらからでも呼べる）
$lcCmd = "@echo off`r`npowershell -NoProfile -ExecutionPolicy Bypass -File `"$lcTarget`" %*`r`n"
$omCmd = "@echo off`r`nuv run `"$omTarget`" %*`r`n"
Set-Content -Path (Join-Path $BinDir 'localclaude.cmd')    -Value $lcCmd -Encoding ascii -NoNewline
Set-Content -Path (Join-Path $BinDir 'ollama-manager.cmd') -Value $omCmd -Encoding ascii -NoNewline
Log "シム作成: $BinDir\localclaude.cmd, ollama-manager.cmd"

# ユーザー PATH へ追加
$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
if (-not $userPath) { $userPath = '' }
if (($userPath -split ';') -notcontains $BinDir) {
  [Environment]::SetEnvironmentVariable('Path', ($BinDir + ';' + $userPath), 'User')
  Log "PATH に $BinDir を追加しました（新しいターミナルで有効）"
} else {
  Log "PATH には既に $BinDir があります"
}

# 前提ツール（インストールはしない・警告のみ）
if (-not (Get-Command ollama -ErrorAction SilentlyContinue)) { Warn 'ollama 未検出: https://ollama.com/download/windows' }
if (-not (Get-Command claude -ErrorAction SilentlyContinue)) { Warn 'claude (Claude Code) 未検出: https://claude.com/claude-code' }

# uv（ollama-manager に必要）— 無ければ導入を尋ねる
if (Get-Command uv -ErrorAction SilentlyContinue) {
  Log "uv 検出: $(uv --version)"
} else {
  Warn 'uv が見つかりません（ollama-manager の実行に必要）'
  $ans = Read-Host 'uv をインストールしますか? [y/N]'
  if ($ans -match '^[yY]') {
    if (Get-Command winget -ErrorAction SilentlyContinue) {
      winget install --id astral-sh.uv -e --source winget
    } else {
      Invoke-RestMethod https://astral.sh/uv/install.ps1 | Invoke-Expression
    }
  } else {
    Warn 'uv 無しでは ollama-manager は動きません: https://docs.astral.sh/uv/'
  }
}

Log 'セットアップ完了。 localclaude --help / ollama-manager --help'
