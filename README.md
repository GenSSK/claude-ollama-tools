# claude-ollama-tools

ローカルの [Ollama](https://ollama.com) で [Claude Code](https://claude.com/claude-code) を動かし、モデルを管理するための macOS 向けコマンド集です。

- **`localclaude`** — Ollama のローカルモデルで Claude Code を起動するラッパー。起動時にモデルを warm ロードし、終了時に自動で offload します。
- **`ollama-manager`** — Ollama モデルを管理する TUI（一覧 / ダウンロード / 削除 / context 長変更 / unload / 詳細）。

> [!WARNING]
> ローカルモデルでの Claude Code は、本家 Anthropic モデルより明確に不安定です。Claude Code は徹底的にツール（関数呼び出し）を使うため、**ツール対応が強いモデル**（例: `qwen2.5-coder`, `qwen3`, `devstral`）を推奨します。小型モデルはツール呼び出しの形式を守れずエラーになりがちです。

## 必要なもの

| | 用途 |
|---|---|
| macOS | Apple Silicon で動作確認（M5 Pro / 64GB） |
| [Ollama](https://ollama.com) | **公式アプリ版を推奨**。Homebrew の formula 版はランナー `llama-server` を欠き推論できない場合があります（`brew install --cask ollama`） |
| [Claude Code](https://claude.com/claude-code) | `claude` コマンド |
| [uv](https://docs.astral.sh/uv/) | `ollama-manager` の実行に必要（依存は初回に自動取得） |
| zsh | `localclaude` の実行に必要 |

`localclaude` は Ollama のネイティブ Anthropic 互換エンドポイント（`/v1/messages`）を自動判定して直結します。無い場合は [LiteLLM](https://github.com/BerriAI/litellm) にフォールバックします（要 `litellm`）。

## インストール

```sh
git clone https://github.com/GenSSK/claude-ollama-tools.git
cd claude-ollama-tools

# PATH の通ったディレクトリにシンボリックリンク（例）
ln -s "$PWD/bin/localclaude"    ~/.local/bin/localclaude
ln -s "$PWD/bin/ollama-manager" ~/.local/bin/ollama-manager
```

Ollama を常時起動にしておくと快適です（公式アプリの設定 → "Launch at login"）。

---

## `localclaude`

Claude Code をローカル Ollama モデルで起動します。

```sh
localclaude [-m|--model <name>] [-l|--list] [--keep] \
            [--bridge auto|native|litellm] [--ctx <n>] [-- <claude args...>]
```

| オプション | 説明 |
|---|---|
| `-m, --model <name>` | 使う Ollama モデル（既定: `$LOCALCLAUDE_MODEL` または `qwen2.5-coder:32b`） |
| `-l, --list` | `ollama list` を表示して終了 |
| `--keep` | 終了時にモデルを offload しない |
| `--bridge <mode>` | `auto`（既定） / `native` / `litellm` |
| `--ctx <n>` | 指定時のみ `<base>-ctx<n>` 派生モデルを作成（既定: 作らず指定モデルをそのまま使用） |
| `-- <args...>` | 以降を素の `claude` にそのまま渡す |

`--model` を省略すると、インストール済みモデルから選択します。

```sh
localclaude                          # モデルを選択して起動
localclaude -m qwen3:30b             # モデル指定
localclaude -- -c                    # claude を --continue で起動
localclaude -m qwen3:30b -- -p "fix" # 非対話実行
```

### 動作

1. `ollama serve` を確認（落ちていれば公式アプリ / `brew services` で起動）
2. `--ctx` 指定時は `<base>-ctx<N>` という派生モデルを Modelfile から自動作成（既存なら再利用）
3. ブリッジを自動判定（native か LiteLLM）
4. モデルを warm ロード
5. 環境変数（`ANTHROPIC_BASE_URL` 等）をサブプロセス内だけに注入して `claude` を起動 — 普段の本家 `claude` は無汚染
6. 終了時に `ollama stop` でモデルを offload（`--keep` で抑止）

環境変数 `LOCALCLAUDE_MODEL` / `LOCALCLAUDE_CTX` / `LOCALCLAUDE_TIMEOUT_MS` で既定値を上書きできます。

---

## `ollama-manager`

Ollama モデルを管理する TUI です。`uv` の単一ファイルスクリプト（[PEP 723](https://peps.python.org/pep-0723/)）で、依存（textual / httpx）は初回に自動取得されます。

```sh
ollama-manager                 # TUI を起動
ollama-manager --check         # 接続確認のみ（exit 0/1）
ollama-manager --list          # モデル一覧をテキスト出力
ollama-manager --host <URL>    # 接続先（既定 $OLLAMA_HOST または http://localhost:11434）
```

### TUI キー操作

| キー | 動作 |
|---|---|
| `r` | 一覧を更新 |
| `p` | モデルを pull（ダウンロード進捗バー） |
| `d` | 選択モデルを削除 |
| `c` | context 長を変えた派生モデルを作成（`<base>-ctx<N>`） |
| `u` | 選択モデルを unload |
| `s` / `Enter` | 詳細表示（パラメータ / num_ctx / テンプレート） |
| `q` | 終了 |

一覧の `CTX` 列は学習時の context 長を表示し、`num_ctx` で上書きされたモデルは `*` 付きで表示します。`c` で作る派生モデルは `localclaude -m <base>-ctx<N>` でそのまま使えます。

---

## 仕組みの補足

- Claude Code は **Anthropic Messages API**（`/v1/messages`）を話します。一方 Ollama は OpenAI 互換のほか、**ネイティブで Anthropic 互換エンドポイントも提供**しています。`localclaude` はこれを実測判定して直結します。
- Claude Code はシステムプロンプト＋ツール定義が巨大なため、十分な context 長（32k 以上）のモデルを使ってください。`localclaude` は既定では**指定したモデルをそのまま使います**。モデル側の context が足りない場合のみ `--ctx <n>` を付けると、`PARAMETER num_ctx <n>` を焼き込んだ `<base>-ctx<n>` 派生モデルを自動作成します。

## ライセンス

[MIT](LICENSE)
