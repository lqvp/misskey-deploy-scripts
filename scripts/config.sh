#!/bin/bash

# コマンドパス
readonly GIT="/usr/bin/git"
readonly DOCKER="/usr/bin/docker"
readonly SUDO="/usr/bin/sudo"
readonly CURL="/usr/bin/curl"

# ステータス表示
readonly STATUS_SUCCESS="✅"
readonly STATUS_ERROR="❌"
readonly STATUS_WARNING="⚠️"

# Discordの色設定
readonly DISCORD_COLOR_SUCCESS=5763719
readonly DISCORD_COLOR_ERROR=16711680
readonly DISCORD_COLOR_WARNING=16776960

# 依存関係チェック
check_dependency() {
  local cmd=$1
  local name=$2
  if ! command -v "$cmd" &> /dev/null; then
    echo "Error: $name が見つかりません。インストールしてください。"
    exit 1
  fi
}

# 必須コマンドの確認
check_dependency "$GIT" "Git"
check_dependency "$DOCKER" "Docker"
check_dependency "$CURL" "cURL"
check_dependency "jq" "jq"