#!/usr/bin/env bash
#
# claude-ollama-tools uninstaller
#
#   ./uninstall.sh [--bin-dir DIR] [--purge] [-h]
#
set -euo pipefail

BIN_DIR="${BIN_DIR:-$HOME/.local/bin}"
PURGE=0
TOOLS="localclaude ollama-manager"

c_b=$'\033[34m'; c_y=$'\033[33m'; c_r=$'\033[31m'; c_g=$'\033[32m'; c_0=$'\033[0m'
log()  { printf '%s[uninstall]%s %s\n'        "$c_b" "$c_0" "$*"; }
ok()   { printf '%s[uninstall]%s %s\n'        "$c_g" "$c_0" "$*"; }
warn() { printf '%s[uninstall] warn:%s %s\n'  "$c_y" "$c_0" "$*" >&2; }
die()  { printf '%s[uninstall] error:%s %s\n' "$c_r" "$c_0" "$*" >&2; exit 1; }

usage() {
  cat <<'USAGE'
claude-ollama-tools uninstaller

  ./uninstall.sh [--bin-dir DIR] [--purge] [-h]

オプション:
  --bin-dir DIR   削除対象のディレクトリ（既定: ~/.local/bin / 環境変数 BIN_DIR でも可）
  --purge         localclaude の状態ディレクトリ ~/.cache/localclaude も削除
  -h, --help      このヘルプ

注: uv / ollama / claude / ダウンロード済みモデルは削除しません。
USAGE
  exit 0
}

while [ $# -gt 0 ]; do
  case "$1" in
    --bin-dir)   shift; [ $# -gt 0 ] || die "--bin-dir に値が必要です"; BIN_DIR="$1" ;;
    --bin-dir=*) BIN_DIR="${1#*=}" ;;
    --purge)     PURGE=1 ;;
    -h|--help)   usage ;;
    *)           die "不明な引数: $1（--help 参照）" ;;
  esac
  shift
done
case "$BIN_DIR" in "~/"*) BIN_DIR="$HOME/${BIN_DIR#"~/"}" ;; esac

removed=0
for t in $TOOLS; do
  dest="$BIN_DIR/$t"
  if [ -L "$dest" ]; then
    tgt="$(readlink "$dest" 2>/dev/null || true)"
    rm -f "$dest"; log "削除(symlink): $dest -> $tgt"; removed=$((removed+1))
  elif [ -f "$dest" ]; then
    rm -f "$dest"; log "削除: $dest"; removed=$((removed+1))
  else
    log "見つからず: $dest"
  fi
done

if [ "$PURGE" -eq 1 ]; then
  if [ -d "$HOME/.cache/localclaude" ]; then
    rm -rf "$HOME/.cache/localclaude"; log "削除: ~/.cache/localclaude"
  fi
fi

ok "uninstall 完了（${removed} 個削除）。uv / ollama / claude / モデルはそのままです。"
