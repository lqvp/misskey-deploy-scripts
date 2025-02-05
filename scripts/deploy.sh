#!/bin/bash

set -euo pipefail

# 設定ファイル名の確認
if [ $# -ne 1 ]; then
    echo "使用方法: $0 <設定名>"
    exit 1
fi

CONFIG_NAME="$1"
CONFIG_FILE="scripts/configs/${CONFIG_NAME}.conf"

# 設定ファイルの存在確認
if [ ! -f "$CONFIG_FILE" ]; then
    echo "エラー: 設定ファイル $CONFIG_FILE が見つかりません"
    exit 1
fi

# 設定の読み込み
source "$CONFIG_FILE"
source "scripts/config.sh"
source "scripts/deploy_functions.sh"

# ログ設定
LOG_DIR="${PWD}/logs/${CONFIG_NAME}"
LOG_FILE="${LOG_DIR}/${CONFIG_NAME}-deploy.log"
mkdir -p "$LOG_DIR" || handle_error "Failed to create log directory: ${LOG_DIR}"

# デプロイ実行
info "======= デプロイ開始: ${CONFIG_NAME} ======="
deploy "$BRANCH"
info "======= デプロイ完了: ${CONFIG_NAME} ======="