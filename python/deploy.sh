#!/usr/bin/env bash
# 旧 scripts/deploy.sh 互換のラッパー。
# 使用方法: ./deploy.sh <インスタンス名> [--dry-run] [--debug]
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)

if ! command -v python3 &>/dev/null; then
    echo "エラー: python3 が見つかりません。インストールしてください。" >&2
    exit 1
fi

# venv があれば利用、なければシステムの python3 + pip パッケージ
if [ -f "$SCRIPT_DIR/.venv/bin/python3" ]; then
    PY="$SCRIPT_DIR/.venv/bin/python3"
else
    PY=python3
fi

# cron など任意の cwd から実行できるようにモジュールを解決できる位置へ移動
cd "$SCRIPT_DIR"

# ユーザーが --config を明示指定した場合はそれを優先する
for arg in "$@"; do
    if [ "$arg" = "--config" ] || [ "${arg#--config=}" != "$arg" ]; then
        exec "$PY" -m misskey_deploy "$@"
    fi
done

exec "$PY" -m misskey_deploy "$@" --config "${DEPLOY_CONFIG:-$SCRIPT_DIR/configs/deploy_config.yaml}"
