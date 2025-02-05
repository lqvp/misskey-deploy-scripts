#!/bin/bash

log() {
    local level="$1"
    local message="$2"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" >>"$LOG_FILE"
}

info() { log "INFO" "$1"; }
error() { log "ERROR" "$1"; }
warn() { log "WARN" "$1"; }

send_discord_notification() {
    local status="$1"
    local message="$2"
    local color="$3"
    local details="${4:-}"
    local max_retries=3
    local retry_delay=5

    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    local payload
    if [[ -n "$details" ]]; then
        payload=$(jq -n \
            --arg title "Deployment Notification" \
            --arg desc "$status $message" \
            --arg color "$color" \
            --arg timestamp "$timestamp" \
            --arg details "$details" \
            '{
                embeds: [{
                    title: $title,
                    description: $desc,
                    color: ($color | tonumber),
                    timestamp: $timestamp,
                    fields: [{
                        name: "Details",
                        value: $details,
                        inline: false
                    }]
                }]
            }')
    else
        payload=$(jq -n \
            --arg title "Deployment Notification" \
            --arg desc "$status $message" \
            --arg color "$color" \
            --arg timestamp "$timestamp" \
            '{
                embeds: [{
                    title: $title,
                    description: $desc,
                    color: ($color | tonumber),
                    timestamp: $timestamp
                }]
            }')
    fi

    local attempt=1
    while ((attempt <= max_retries)); do
        local response
        response=$($CURL -H "Content-Type: application/json" \
            -d "$payload" \
            -w "%{http_code}" \
            -s -o /dev/null \
            "$DISCORD_WEBHOOK_URL")

        if [[ "$response" == "204" ]]; then
            info "Discord通知が送信されました"
            return 0
        fi

        warn "Discord通知失敗 (試行 $attempt/$max_retries) ステータス: $response"
        ((attempt++))
        sleep "$retry_delay"
    done

    error "Discord通知を$max_retries回試行しましたが失敗しました"
    return 1
}

handle_error() {
    local error_message="$1"
    error "$error_message"
    send_discord_notification "$STATUS_ERROR" \
        "エラーが発生しました" \
        "$DISCORD_COLOR_ERROR" \
        "**エラー詳細:**\n\`\`\`\n$error_message\n\`\`\`" || true
    exit 1
}

deploy() {
    local branch="$1"

    cd "$REPO_DIR" || handle_error "リポジトリディレクトリが見つかりません: $REPO_DIR"

    info "ブランチ $branch のデプロイを開始します"

    local current_hash
    current_hash=$($GIT rev-parse HEAD)

    info "ブランチ $branch の更新を確認中..."
    $GIT fetch origin "$branch"

    local remote_hash
    remote_hash=$($GIT rev-parse "origin/$branch")

    if [[ "$current_hash" == "$remote_hash" ]]; then
        info "更新はありません"
        return 0
    fi

    local commit_message commit_author commit_link
    commit_message=$($GIT log --format=%B -n 1 "$remote_hash")
    commit_author=$($GIT log --format=%an -n 1 "$remote_hash")
    commit_link="${REPO_URL}/commit/${remote_hash}"

    local update_details="**コミット情報:**
🔗 [${remote_hash:0:7}]($commit_link)
👤 作者: $commit_author
📝 メッセージ: $commit_message"

    send_discord_notification "$STATUS_WARNING" \
        "更新を検出しました" \
        "$DISCORD_COLOR_WARNING" \
        "$update_details"

    info "ブランチ $branch から更新を取得中..."
    $GIT pull origin "$branch"

    info "Dockerコンテナのビルドと起動..."
    if $DOCKER compose up -d --build; then
        local deploy_details="**デプロイ情報:**
🔗 [${remote_hash:0:7}]($commit_link) をデプロイしました
🐳 Dockerコンテナがビルドされ起動しました"

        send_discord_notification "$STATUS_SUCCESS" \
            "デプロイ完了 🎉" \
            "$DISCORD_COLOR_SUCCESS" \
            "$deploy_details"
    else
        handle_error "Docker composeの実行に失敗しました"
    fi
}