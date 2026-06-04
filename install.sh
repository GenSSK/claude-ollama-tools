#!/usr/bin/env bash
#
# claude-ollama-tools installer
#
#   ./install.sh [--bin-dir DIR] [--copy] [-h]
#
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="${BIN_DIR:-$HOME/.local/bin}"   # 既定のインストール先（環境変数 BIN_DIR でも可）
MODE="symlink"                           # symlink（既定）| copy
TOOLS="localclaude ollama-manager"
OS="$(uname -s)"

c_b=$'\033[34m'; c_y=$'\033[33m'; c_r=$'\033[31m'; c_g=$'\033[32m'; c_0=$'\033[0m'
log()  { printf '%s[install]%s %s\n'        "$c_b" "$c_0" "$*"; }
ok()   { printf '%s[install]%s %s\n'        "$c_g" "$c_0" "$*"; }
warn() { printf '%s[install] warn:%s %s\n'  "$c_y" "$c_0" "$*" >&2; }
die()  { printf '%s[install] error:%s %s\n' "$c_r" "$c_0" "$*" >&2; exit 1; }

usage() {
  cat <<'USAGE'
claude-ollama-tools installer

  ./install.sh [--bin-dir DIR] [--copy] [-h]

オプション:
  --bin-dir DIR   インストール先ディレクトリ（既定: ~/.local/bin / 環境変数 BIN_DIR でも可）
  --copy          コピーでインストール（既定: このリポジトリへの symlink。symlink なら git pull で更新が反映）
  --symlink       symlink でインストール（既定）
  -h, --help      このヘルプ

例:
  ./install.sh
  ./install.sh --bin-dir /usr/local/bin
  ./install.sh --copy
USAGE
  exit 0
}

while [ $# -gt 0 ]; do
  case "$1" in
    --bin-dir)   shift; [ $# -gt 0 ] || die "--bin-dir に値が必要です"; BIN_DIR="$1" ;;
    --bin-dir=*) BIN_DIR="${1#*=}" ;;
    --copy)      MODE="copy" ;;
    --symlink)   MODE="symlink" ;;
    -h|--help)   usage ;;
    *)           die "不明な引数: $1（--help 参照）" ;;
  esac
  shift
done
case "$BIN_DIR" in "~/"*) BIN_DIR="$HOME/${BIN_DIR#"~/"}" ;; esac   # 先頭 ~/ を展開

# yes/no を尋ねる（非対話なら no 扱い）
ask() {
  [ -t 0 ] || return 1
  printf '%s [y/N] ' "$1" >&2
  read -r _ans || return 1
  case "$_ans" in [yY]|[yY][eE][sS]) return 0 ;; *) return 1 ;; esac
}

# ── ツールを配置 ───────────────────────────────────────────────
mkdir -p "$BIN_DIR"
for t in $TOOLS; do
  src="$REPO_DIR/bin/$t"
  dest="$BIN_DIR/$t"
  [ -f "$src" ] || die "$src が見つかりません（リポジトリ内で実行してください）"
  chmod +x "$src" 2>/dev/null || true
  if [ "$MODE" = "symlink" ]; then
    ln -sf "$src" "$dest"; log "symlink: $dest -> $src"
  else
    cp "$src" "$dest"; chmod +x "$dest"; log "copy: $dest"
  fi
done
ok "インストール完了: ${BIN_DIR}（${MODE}）"

# ── PATH 確認 ─────────────────────────────────────────────────
case ":$PATH:" in
  *":$BIN_DIR:"*) ;;
  *) warn "$BIN_DIR は PATH に入っていません。シェル設定に追加してください:"
     printf '    bash/zsh: %s\n' "export PATH=\"$BIN_DIR:\$PATH\"" >&2
     printf '    fish:     %s\n' "fish_add_path $BIN_DIR" >&2 ;;
esac

# ── 前提ツールの確認（インストールはしない・警告のみ）─────────────
if ! command -v ollama >/dev/null 2>&1; then
  if [ "$OS" = "Darwin" ]; then
    warn "ollama 未検出。公式アプリ推奨: brew install --cask ollama"
  else
    warn "ollama 未検出。Linux: curl -fsSL https://ollama.com/install.sh | sh"
  fi
fi
command -v claude >/dev/null 2>&1 || warn "claude (Claude Code) 未検出: https://claude.com/claude-code"

# ── uv（ollama-manager の実行に必要）─ 無ければ導入を尋ねる ──────
if command -v uv >/dev/null 2>&1; then
  log "uv 検出: $(uv --version 2>/dev/null || echo present)"
else
  warn "uv が見つかりません（ollama-manager の実行に必要）"
  if ask "uv をインストールしますか?"; then
    if command -v brew >/dev/null 2>&1; then
      if brew install uv; then ok "uv をインストールしました"; else warn "brew install uv に失敗"; fi
    else
      if curl -LsSf https://astral.sh/uv/install.sh | sh; then
        ok "uv をインストールしました（新しいシェルで PATH を再読み込みしてください）"
      else
        warn "uv インストーラの実行に失敗しました"
      fi
    fi
  else
    warn "uv 無しでは ollama-manager は動きません。後で導入を: https://docs.astral.sh/uv/"
  fi
fi

ok "セットアップ完了。  localclaude --help  /  ollama-manager --help"
