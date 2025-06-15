#!/bin/bash

# notifications.sh

# 依存する変数 (CURL, JQ, 各種Webhook URL, Token, STATUS定数など) は
# 呼び出し元のスクリプト (deploy_functions.sh経由でdeploy.sh) で設定されていることを期待します。
# INSTANCE_NAME も同様です。
# LOG_FILE, DEBUG_MODE は logging.sh 側でフォールバックがあるのでここでは必須ではない

# logging.sh が source されている前提 (debug, info, warn, error 関数を使用するため)
if ! command -v info &> /dev/null || ! command -v debug &> /dev/null; then
    echo "ERROR: logging.sh is not sourced or info/debug functions are not available. Cannot proceed with notifications.sh." >&2
    exit 1
fi


send_discord_notification() {
    local status="$1"
    local message="$2"
    local color="$3"
    local details="${4:-}"
    local max_retries=3
    local retry_delay=5

    if [[ -z "$DISCORD_WEBHOOK_URL" ]]; then
        debug "Discord Webhook URLが設定されていません (${INSTANCE_NAME})。通知をスキップします。"
        return 0
    fi

    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local instance_message_header="Instance: ${INSTANCE_NAME}"

    local payload_description="${status} ${message}"
    local payload_fields_json # 初期化

    # Details内の \n を解釈し、jqに渡す際に適切に処理されるようにする
    local details_with_proper_newlines
    if [[ -n "$details" ]]; then
        local details_escaped_for_echo_e="${details//\\\\n/\\n}" # \\n を \n に置換
        details_with_proper_newlines=$(echo -e "$details_escaped_for_echo_e") # -e でエスケープシーケンスを解釈
    fi

    if [[ -n "$details_with_proper_newlines" ]]; then
        payload_fields_json=$(jq -n \
            --arg name1 "${instance_message_header}" \
            --arg value1 " " \
            --arg name2 "Details" \
            --arg value2 "$details_with_proper_newlines" \
            '[{name: $name1, value: $value1, inline: false}, {name: $name2, value: $value2, inline: false}]')
    else
        payload_fields_json=$(jq -n \
            --arg name1 "${instance_message_header}" \
            --arg value1 " " \
            '[{name: $name1, value: $value1, inline: false}]')
    fi

    local payload
    payload=$(jq -n \
        --arg title "Deployment Notification" \
        --arg desc "$payload_description" \
        --arg color "$color" \
        --arg timestamp "$timestamp" \
        --argjson fields "$payload_fields_json" \
        '{
            embeds: [{
                title: $title,
                description: $desc,
                color: ($color | tonumber),
                timestamp: $timestamp,
                fields: $fields
            }]
        }')

    # jqのエラーチェック
    if [[ -z "$payload" ]]; then
        error "Discord通知のペイロード生成に失敗しました (${INSTANCE_NAME})。"
        return 1
    fi

    local attempt=1
    while ((attempt <= max_retries)); do
        local response_code
        response_code=$($CURL -H "Content-Type: application/json" \
            -d "$payload" \
            -w "%{http_code}" \
            -s -o /dev/null \
            "$DISCORD_WEBHOOK_URL")

        if [[ "$response_code" == "204" ]]; then
            info "Discord通知が送信されました (${INSTANCE_NAME})"
            return 0
        fi

        warn "Discord通知失敗 (Attempt: $attempt/$max_retries, Status: $response_code, Instance: ${INSTANCE_NAME})"
        ((attempt++))
        sleep "$retry_delay"
    done

    error "Discord通知を$max_retries回試行しましたが失敗しました (${INSTANCE_NAME})"
    return 1
}

send_misskey_notification() {
    local status_symbol="$1"
    local original_message="$2"
    local original_details="$3"

    if [[ "$USE_MISSKEY_NOTIFICATION" != "true" ]]; then
        debug "Misskey通知が無効です (${INSTANCE_NAME})。スキップします。"
        return 0
    fi
    if [[ -z "$MISSKEY_HOST" || -z "$MISSKEY_TOKEN" ]]; then
        warn "Misskeyホストまたはトークンが設定されていません (${INSTANCE_NAME})。通知をスキップします。"
        return 0
    fi

    # Process inputs to interpret \n etc.
    local processed_message
    local message_escaped_for_echo_e="${original_message//\\\\n/\\n}" # \\n を \n に置換
    processed_message=$(echo -e "$message_escaped_for_echo_e")

    # 詳細メッセージの \n は jq が処理するので echo -e は不要
    # バッククォートのエスケープも不要 (details は既にMisskey Markdown形式であることを期待)

    local text_content="${status_symbol} **Deployment Notification (${INSTANCE_NAME})**\n${processed_message}"
    if [[ -n "$original_details" ]]; then
        text_content="${text_content}\n\n${original_details}"
    fi


    local payload
    payload=$(jq -n \
        --arg text "$text_content" \
        --arg visibility "$MISSKEY_VISIBILITY" \
        --arg localOnlyStr "$MISSKEY_LOCAL_ONLY" \
        --arg i "$MISSKEY_TOKEN" \
        '{
            text: $text,
            visibility: $visibility,
            localOnly: ($localOnlyStr == "true"),
            i: $i
        }')

    if [[ -z "$payload" ]]; then
        error "Misskey通知のペイロード生成に失敗しました (${INSTANCE_NAME})。"
        return 1
    fi

    local max_retries=3 retry_delay=5 attempt=1 success=0
    while ((attempt <= max_retries)); do
        local response_code
        response_code=$($CURL -X POST \
            -H "Content-Type: application/json" \
            -d "$payload" \
            -w "%{http_code}" \
            -s -o /dev/null \
            "${MISSKEY_HOST}/api/notes/create")

        if [[ "$response_code" == "200" ]]; then
            info "Misskey通知が送信されました (${INSTANCE_NAME})"
            success=1
            break
        else
            warn "Misskey通知失敗 (Attempt: $attempt/$max_retries, Status: $response_code, Instance: ${INSTANCE_NAME})"
            sleep "$retry_delay"
            ((attempt++))
        fi
    done

    ((success == 0)) && error "Misskey通知を${max_retries}回試行しましたが失敗しました (${INSTANCE_NAME})"
    return $((success == 0 ? 1 : 0))
}

handle_error() {
    local error_message="$1"
    local exit_code="${2:-1}" # Default exit code is 1

    # Get caller information
    local caller_info
    caller_info=$(caller 0) # Output: <line_number> <function_name> <script_path>
    local line_num func_name script_file
    # caller_info の形式は "LINENO FUNCNAME FILENAME" なので、適切に読み込む
    read -r line_num func_name script_file <<< "$caller_info"
    # script_file がフルパスで取得される場合があるので、ファイル名のみを抽出
    script_file=$(basename "$script_file")

    local error_location_info="エラー発生箇所: \`${script_file}\` の \`${func_name}\` 関数、\`${line_num}\` 行目"

    # ログにもエラー発生箇所を記録
    error "$error_message (Instance: ${INSTANCE_NAME}) - ${error_location_info}"

    # Details内のバッククォートをエスケープ (Markdown用)
    local escaped_error_message_for_md="${error_message//\`/\\\`}"
    local error_details_for_notification="**エラー発生 (Instance: ${INSTANCE_NAME}):**\n"
    error_details_for_notification+="${error_location_info}\n\n" # 箇所とメッセージの間に空行を追加
    error_details_for_notification+="エラーメッセージ:\n\`\`\`\n${escaped_error_message_for_md}\n\`\`\`\nスクリプトの実行が停止しました。"

    # STATUS_ERROR, DISCORD_COLOR_ERROR は呼び出し元で定義されている想定
    send_discord_notification "${STATUS_ERROR:-ERROR}" \
        "デプロイメントエラー" \
        "${DISCORD_COLOR_ERROR:-15548997}" \
        "$error_details_for_notification"

    send_misskey_notification "${STATUS_ERROR:-❗}" \
        "デプロイメントエラー" \
        "$error_details_for_notification"

    exit "$exit_code"
}