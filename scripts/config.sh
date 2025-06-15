#!/bin/bash

# コマンド名 (通常はPATHが通っていることを期待)
readonly GIT="git"
readonly DOCKER="docker"
readonly CURL="curl"
readonly YQ="yq"
readonly BC="bc"
readonly JQ="jq"

# ステータス表示
# shellcheck disable=SC2034
readonly STATUS_SUCCESS="✅"
# shellcheck disable=SC2034
readonly STATUS_ERROR="❌"
# shellcheck disable=SC2034
readonly STATUS_WARNING="⚠️"
# shellcheck disable=SC2034
readonly STATUS_INFO="ℹ️"

# Discordの色設定
# shellcheck disable=SC2034
readonly DISCORD_COLOR_SUCCESS="3066993"
# shellcheck disable=SC2034
readonly DISCORD_COLOR_ERROR="15158332"
# shellcheck disable=SC2034
readonly DISCORD_COLOR_WARNING="15105570"
# shellcheck disable=SC2034
readonly DISCORD_COLOR_INFO="3447003" 

# 依存関係チェック関数
check_dependency() {
  local cmd_name=$1 # コマンド名 (例: "git")
  local display_name=$2 # 表示名 (例: "Git")
  if ! command -v "$cmd_name" &> /dev/null; then
    echo "Error: $display_name ($cmd_name) が見つかりません。インストールしてください。"
    exit 1
  fi
}

# 必須コマンドの確認
# GIT, DOCKER, CURL は変数経由でチェック、他は直接コマンド名を渡す
check_dependency "$GIT" "Git"
check_dependency "$DOCKER" "Docker"
check_dependency "$CURL" "cURL"
check_dependency "$JQ" "jq"
check_dependency "$YQ" "yq"
check_dependency "$BC" "bc"