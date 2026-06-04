<#
  claude-ollama-tools uninstaller (Windows / PowerShell)

    powershell -ExecutionPolicy Bypass -File .\uninstall.ps1 [-BinDir <dir>] [-Purge]

      -BinDir <dir>   対象（既定: %USERPROFILE%\.local\bin）
      -Purge          状態ディレクトリ（%LOCALAPPDATA%\localclaude）も削除

  注: uv / ollama / claude / モデル / PATH 設定は削除しません。
#>
param(
  [string]$BinDir = (Join-Path $env:USERPROFILE '.local\bin'),
  [switch]$Purge
)
function Log($m) { Write-Host "[uninstall] $m" }

$removed = 0
foreach ($f in @('localclaude.cmd', 'ollama-manager.cmd', 'localclaude.ps1', 'ollama-manager')) {
  $p = Join-Path $BinDir $f
  if (Test-Path $p) { Remove-Item $p -Force; Log "削除: $p"; $removed++ }
}

if ($Purge) {
  $state = if ($env:LOCALCLAUDE_STATE) { $env:LOCALCLAUDE_STATE } else { Join-Path $env:LOCALAPPDATA 'localclaude' }
  if (Test-Path $state) { Remove-Item $state -Recurse -Force; Log "削除: $state" }
}

Log "uninstall 完了（$removed 個削除）。uv / ollama / claude / モデル / PATH 設定はそのままです。"
