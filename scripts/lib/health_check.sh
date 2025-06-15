#!/bin/bash

# shellcheck source=../config_parser.sh
SCRIPT_DIR_LIB=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# shellcheck source=../config_parser.sh
source "$SCRIPT_DIR_LIB/../config_parser.sh"
# shellcheck source=./logging.sh
source "$SCRIPT_DIR_LIB/logging.sh"
# shellcheck source=./notifications.sh
source "$SCRIPT_DIR_LIB/notifications.sh"

perform_health_check() {
    info "ヘルスチェックを開始します..."

    local hc_enabled
    hc_enabled=$(get_instance_setting "$INSTANCE_NAME" ".health_check.enabled" "false")

    if [[ "$hc_enabled" != "true" ]]; then
        info "インスタンス '${INSTANCE_NAME}' のヘルスチェックは無効です。スキップします。"
        return 0
    fi

    local hc_url hc_timeout hc_retries hc_retry_delay hc_expected_status hc_expected_contains
    hc_url=$(get_instance_setting "$INSTANCE_NAME" ".health_check.url")
    hc_timeout=$(get_instance_setting "$INSTANCE_NAME" ".health_check.timeout_seconds" "10")
    hc_retries=$(get_instance_setting "$INSTANCE_NAME" ".health_check.retries" "3")
    hc_retry_delay=$(get_instance_setting "$INSTANCE_NAME" ".health_check.retry_delay_seconds" "5")
    hc_expected_status=$(get_instance_setting "$INSTANCE_NAME" ".health_check.expected_status_code" "200")
    hc_expected_contains=$(get_instance_setting "$INSTANCE_NAME" ".health_check.expected_response_contains")

    if [[ -z "$hc_url" ]]; then
        warn "ヘルスチェックURLが設定されていません。スキップします。"
        return 0
    fi

    info "ヘルスチェック実行: URL=$hc_url, Timeout=${hc_timeout}s, Retries=$hc_retries, Delay=${hc_retry_delay}s"

    local attempt=0
    local success=false
    local http_status
    local response_body

    while [[ $attempt -le $hc_retries ]]; do
        attempt=$((attempt + 1))
        info "ヘルスチェック試行 $attempt/$((hc_retries + 1)) ..."

        local curl_output
        # config.sh で定義された CURL 変数を使う想定
        curl_output=$($CURL -sS -w "\n%{http_code}" --max-time "$hc_timeout" --connect-timeout 5 "$hc_url" 2>&1)
        
        http_status=$(echo -e "$curl_output" | tail -n1)
        response_body=$(echo -e "$curl_output" | sed '$d')

        if [[ "$http_status" == "$hc_expected_status" ]]; then
            if [[ -n "$hc_expected_contains" ]]; then
                if echo "$response_body" | grep -qF -- "$hc_expected_contains"; then
                    success=true
                    info "ヘルスチェック成功 (ステータス: $http_status, 内容一致: '$hc_expected_contains')"
                    break
                else
                    warn "ヘルスチェック失敗 (試行 $attempt): ステータスは $http_status で期待通りですが、レスポンス内容に期待する文字列 '$hc_expected_contains' が見つかりません。"
                    debug "レスポンスボディ:\n$response_body"
                fi
            else
                success=true
                info "ヘルスチェック成功 (ステータス: $http_status)"
                break
            fi
        else
            warn "ヘルスチェック失敗 (試行 $attempt): 期待するステータス $hc_expected_status を得られませんでした (実際のステータス: $http_status)。"
            debug "レスポンスボディ:\n$response_body"
        fi

        if [[ $attempt -le $hc_retries ]]; then
            info "$hc_retry_delay 秒後にリトライします..."
            sleep "$hc_retry_delay"
        fi
    done

    local health_check_details="対象URL: $hc_url\n期待ステータス: $hc_expected_status"
    if [[ -n "$hc_expected_contains" ]]; then
        health_check_details+="\n期待する内容: $hc_expected_contains"
    fi

    # config.sh で定義された STATUS_SUCCESS, DISCORD_COLOR_SUCCESS などを使う想定
    if $success; then
        health_check_details+="\n結果: 成功 (ステータス $http_status)"
        send_discord_notification "$STATUS_SUCCESS" "ヘルスチェック完了 🎉" "$DISCORD_COLOR_SUCCESS" "$health_check_details"
        send_misskey_notification "$STATUS_SUCCESS" "ヘルスチェック完了 🎉" "$health_check_details"
    else
        health_check_details+="\n結果: 失敗 (最終ステータス $http_status)"
        send_discord_notification "$STATUS_WARNING" "ヘルスチェック失敗 🚨" "$DISCORD_COLOR_WARNING" "$health_check_details"
        send_misskey_notification "$STATUS_WARNING" "ヘルスチェック失敗 🚨" "$health_check_details"
        warn "最終的なヘルスチェックに失敗しました。"
    fi
    info "ヘルスチェック完了。"
}
