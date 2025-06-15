#!/bin/bash

set -euo pipefail

# スクリプトのディレクトリを取得
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
PROJECT_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)

# 設定ファイル名の確認 (インスタンス名)
if [ $# -ne 1 ]; then
    echo "使用方法: $0 <インスタンス名>"
    echo "利用可能なインスタンス名は deploy_config.yaml で定義されています。"
    exit 1
fi
INSTANCE_NAME="$1"

# --- 新しい設定システムの読み込み ---
MAIN_CONFIG_FILE="$PROJECT_ROOT/scripts/configs/deploy_config.yaml" # YAML設定ファイル
CONFIG_PARSER_SCRIPT="$SCRIPT_DIR/config_parser.sh"

if [ ! -f "$MAIN_CONFIG_FILE" ]; then
    echo "エラー: メイン設定ファイル $MAIN_CONFIG_FILE が見つかりません。"
    echo "cp scripts/configs/deploy_config.yaml.example scripts/configs/deploy_config.yaml して設定してください。"
    exit 1
fi
if [ ! -f "$CONFIG_PARSER_SCRIPT" ]; then
    echo "エラー: 設定パーサースクリプト $CONFIG_PARSER_SCRIPT が見つかりません。"
    exit 1
fi
source "$CONFIG_PARSER_SCRIPT"

# パーサー初期化 (yqコマンドのチェックなど)
if ! initialize_parser; then
    exit 1
fi
# --- ここまで新しい設定システムの読み込み ---

source "$(dirname "$0")/lib/logging.sh"

# --- 既存のconfig.shとdeploy_functions.shの読み込み ---
# config.sh は依存関係チェックのために読み込む。変数定義は新しい設定システムから行う。
source "$SCRIPT_DIR/config.sh" # GIT, DOCKER, CURL, STATUS_*, DISCORD_COLOR_* などが定義される
source "$SCRIPT_DIR/deploy_functions.sh"
# --- ここまで ---

# --- インスタンス設定の取得 ---
# enabled フラグを確認
INSTANCE_ENABLED=$(get_instance_setting "$INSTANCE_NAME" ".enabled" "false")
if [[ "$INSTANCE_ENABLED" != "true" ]]; then
    echo "情報: インスタンス '$INSTANCE_NAME' は設定ファイルで無効化されています。処理をスキップします。"
    exit 0
fi

REPO_DIR=$(get_instance_setting "$INSTANCE_NAME" ".repo_dir")
REPO_URL=$(get_instance_setting "$INSTANCE_NAME" ".repo_url")
BRANCH=$(get_instance_setting "$INSTANCE_NAME" ".branch")

if [[ -z "$REPO_DIR" ]] || [[ -z "$REPO_URL" ]] || [[ -z "$BRANCH" ]]; then
    error "インスタンス '$INSTANCE_NAME' の必須設定 (repo_dir, repo_url, branch) が不足しています。"
    exit 1
fi

# Discord Webhook URL (インスタンス固有 -> グローバル -> なし)
DISCORD_WEBHOOK_URL=$(get_instance_or_global_setting "$INSTANCE_NAME" ".discord_webhook_url" ".discord_webhook_url")

# Misskey通知設定
USE_MISSKEY_NOTIFICATION=$(get_instance_or_global_setting "$INSTANCE_NAME" ".misskey_notification.enabled" ".misskey_notification.enabled" "false")
MISSKEY_HOST=$(get_instance_or_global_setting "$INSTANCE_NAME" ".misskey_notification.host" ".misskey_notification.host")
MISSKEY_TOKEN=$(get_instance_or_global_setting "$INSTANCE_NAME" ".misskey_notification.token" ".misskey_notification.token")
MISSKEY_VISIBILITY=$(get_instance_or_global_setting "$INSTANCE_NAME" ".misskey_notification.visibility" ".misskey_notification.visibility" "public")
MISSKEY_LOCAL_ONLY=$(get_instance_or_global_setting "$INSTANCE_NAME" ".misskey_notification.local_only" ".misskey_notification.local_only" "false")

# デプロイフィルタ (後ほど deploy_functions.sh で使用)
GLOBAL_EXCLUDE_PATHS_RAW=$(get_global_array_setting ".deploy_filters.exclude_paths")
INSTANCE_EXCLUDE_PATHS_RAW=$(get_instance_array_setting "$INSTANCE_NAME" ".deploy_filters.exclude_paths")
INSTANCE_INCLUDE_PATHS_RAW=$(get_instance_array_setting "$INSTANCE_NAME" ".deploy_filters.include_paths")

# 配列に変換
readarray -t GLOBAL_EXCLUDE_PATHS <<< "$GLOBAL_EXCLUDE_PATHS_RAW"
readarray -t INSTANCE_EXCLUDE_PATHS <<< "$INSTANCE_EXCLUDE_PATHS_RAW"
readarray -t INSTANCE_INCLUDE_PATHS <<< "$INSTANCE_INCLUDE_PATHS_RAW"

# --- ここまでインスタンス設定の取得 ---

# ログ設定 (ログファイル名はインスタンス名ベースに変更)
LOG_DIR="${PROJECT_ROOT}/logs/${INSTANCE_NAME}"
LOG_FILE="${LOG_DIR}/${INSTANCE_NAME}-deploy.log"
mkdir -p "$LOG_DIR" || { echo "エラー: ログディレクトリの作成に失敗しました: ${LOG_DIR}"; exit 1; } # handle_error はまだ使えない可能性

# ログ関数内で使用される LOG_FILE をエクスポート (deploy_functions.sh で参照するため)
export LOG_FILE

# デプロイ実行
info "======= デプロイ開始: ${INSTANCE_NAME} ======="
deploy "$BRANCH" # deploy関数は deploy_functions.sh にある
info "======= デプロイ完了: ${INSTANCE_NAME} ======="
