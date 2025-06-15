#!/bin/bash

# shellcheck source=./lib/logging.sh
source "$SCRIPT_DIR/lib/logging.sh"
# shellcheck source=./lib/notifications.sh
source "$SCRIPT_DIR/lib/notifications.sh"

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

        # HTTPステータスコードとレスポンスボディを同時に取得
        # -sS: エラーメッセージを表示し、プログレスメーターを非表示
        # -w "%{http_code}": 最後にHTTPステータスコードを出力
        # --max-time: 最大許容時間
        # --connect-timeout: 接続タイムアウト
        # --retry, --retry-delay: curl自身のリトライ機能 (今回は手動ループのため0に)
        local curl_output
        curl_output=$($CURL -sS -w "\n%{http_code}" --max-time "$hc_timeout" --connect-timeout 5 "$hc_url" 2>&1)
        
        # curl_output の最後の行がHTTPステータスコード、それより前がレスポンスボディ
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

    if $success; then
        health_check_details+="\n結果: 成功 (ステータス $http_status)"
        send_discord_notification "$STATUS_SUCCESS" "ヘルスチェック成功" "$DISCORD_COLOR_SUCCESS" "$health_check_details"
        send_misskey_notification "$STATUS_SUCCESS" "ヘルスチェック成功" "$health_check_details"
    else
        health_check_details+="\n結果: 失敗 (最終ステータス $http_status)"
        send_discord_notification "$STATUS_WARNING" "ヘルスチェック失敗" "$DISCORD_COLOR_WARNING" "$health_check_details"
        send_misskey_notification "$STATUS_WARNING" "ヘルスチェック失敗" "$health_check_details"
        warn "最終的なヘルスチェックに失敗しました。"
    fi
    info "ヘルスチェック完了。"
}


deploy() {
    local branch="$1"

    cd "$REPO_DIR" || handle_error "リポジトリディレクトリが見つかりません: $REPO_DIR"

    info "ブランチ $branch のデプロイを開始します"

    local current_hash
    current_hash=$($GIT rev-parse HEAD)

    info "ブランチ $branch の更新を確認中..."
    if ! $GIT fetch origin "$branch" --quiet; then
        handle_error "Git fetchに失敗しました。"
    fi

    local remote_hash
    remote_hash=$($GIT rev-parse "origin/$branch")

    if [[ "$current_hash" == "$remote_hash" ]]; then
        info "更新はありません。デプロイをスキップします。"
        # 必要であれば、更新がなかったことを通知する処理をここに追加できます。
        # 例: send_discord_notification "$STATUS_INFO" "更新なし" "$DISCORD_COLOR_INFO" "インスタンス ${INSTANCE_NAME} は最新の状態です。"
        return 0
    fi

    info "変更されたファイルを確認中 ($current_hash..$remote_hash)..."
    local changed_files_raw
    changed_files_raw=$($GIT diff --name-only "$current_hash" "$remote_hash")
    if [[ -z "$changed_files_raw" ]]; then
        info "コミットはありますが、ファイル変更は検出されませんでした。デプロイをスキップします。"
        return 0
    fi

    local changed_files=()
    readarray -t changed_files <<< "$changed_files_raw"

    info "検出された変更ファイル (${#changed_files[@]} 件):\n$changed_files_raw"

    local filter_log_details=""
    local files_after_include_filter=()
    local files_after_instance_exclude=()
    local final_files_to_deploy=()

    # --- フィルタリング処理開始 ---
    local original_changed_files_count=${#changed_files[@]}
    info "**フィルター適用プロセス:**"

    # 1. Includeフィルターを適用 (インスタンス固有設定を優先、なければグローバル設定を参照)
    local -a EFFECTIVE_INCLUDE_PATHS
    local include_source_message=""

    # INSTANCE_INCLUDE_PATHS と GLOBAL_INCLUDE_PATHS は事前に設定されている想定
    if ((${#INSTANCE_INCLUDE_PATHS[@]} > 0)); then
        EFFECTIVE_INCLUDE_PATHS=("${INSTANCE_INCLUDE_PATHS[@]}")
        include_source_message="1. インスタンス Include設定を使用 (${EFFECTIVE_INCLUDE_PATHS[*]}):"
    elif ((${#GLOBAL_INCLUDE_PATHS[@]} > 0)); then # GLOBAL_INCLUDE_PATHS をここで参照 (事前に設定されている前提)
        EFFECTIVE_INCLUDE_PATHS=("${GLOBAL_INCLUDE_PATHS[@]}")
        include_source_message="1. グローバル Include設定を使用 (${EFFECTIVE_INCLUDE_PATHS[*]}):"
    else
        include_source_message="1. Include設定 (インスタンス/グローバル共) なし: 全ファイル対象"
        # EFFECTIVE_INCLUDE_PATHS は空のまま
    fi
    info "$include_source_message"

    # files_after_include_filter はこのステージの結果を格納する変数 (line 140で宣言済み)
    if ((${#EFFECTIVE_INCLUDE_PATHS[@]} > 0)); then
        for file in "${changed_files[@]}"; do
            local matched_include=false
            local matched_include_pattern=""
            for pattern in "${EFFECTIVE_INCLUDE_PATHS[@]}"; do
                # シェルグロブを使用して前方一致と完全一致をサポート
                if [[ "$file" == $pattern* || "$file" == $pattern ]]; then
                    matched_include=true
                    matched_include_pattern="$pattern"
                    break
                fi
            done
            if $matched_include; then
                files_after_include_filter+=("$file")
                info "  - $file (Include一致: $matched_include_pattern)"
            else
                info "  - $file (Include不一致)"
            fi
        done
    else
        # Includeフィルターが指定されていない場合、全ての変更ファイルがこのフィルターを通過
        files_after_include_filter=("${changed_files[@]}")
    fi
    local include_filter_count=${#files_after_include_filter[@]}
    info "  Includeフィルター適用後 残り: $include_filter_count 件"


    # 2. インスタンス Exclude フィルター
    if ((${#INSTANCE_EXCLUDE_PATHS[@]} > 0)); then
        info "2. インスタンス Exclude (${INSTANCE_EXCLUDE_PATHS[*]}):"
        for file in "${files_after_include_filter[@]}"; do
            local matched_exclude=false
            local matched_exclude_pattern=""
            for pattern in "${INSTANCE_EXCLUDE_PATHS[@]}"; do
                # shellcheck disable=SC2053
                if [[ "$file" == $pattern ]]; then # Glob match
                    matched_exclude=true
                    matched_exclude_pattern="$pattern"
                    break
                fi
            done
            if $matched_exclude; then
                info "  - $file (Exclude一致: $matched_exclude_pattern)"
            else
                info "  DEBUG: Adding '$file' to files_after_instance_exclude. Count BEFORE: ${#files_after_instance_exclude[@]}"
                files_after_instance_exclude+=("$file")
                info "  DEBUG: Added '$file'. Count AFTER: ${#files_after_instance_exclude[@]}"
            fi
        done
    else
        files_after_instance_exclude=("${files_after_include_filter[@]}")
        info "2. インスタンス Exclude: 指定なし"
        info "  インスタンスExclude (指定なしのため全件通過)後 残り: ${#files_after_instance_exclude[@]} 件"
fi


    # 3. グローバル Exclude フィルター
    if ((${#GLOBAL_EXCLUDE_PATHS[@]} > 0)); then
        info "3. グローバル Exclude (${GLOBAL_EXCLUDE_PATHS[*]}):"
        for file in "${files_after_instance_exclude[@]}"; do
            local matched_exclude=false
            local matched_exclude_pattern=""
            for pattern in "${GLOBAL_EXCLUDE_PATHS[@]}"; do
                # shellcheck disable=SC2053
                if [[ "$file" == $pattern ]]; then # Glob match
                    matched_exclude=true
                    matched_exclude_pattern="$pattern"
                    break
                fi
            done
            if $matched_exclude; then
                info "  - $file (グローバルExclude一致: $matched_exclude_pattern)"
            else
                final_files_to_deploy+=("$file")
            fi
        done
    else
        final_files_to_deploy=("${files_after_instance_exclude[@]}")
        info "3. グローバル Exclude: 指定なし"
    fi
    if ((${#GLOBAL_EXCLUDE_PATHS[@]} > 0)); then
      local final_deploy_count=${#final_files_to_deploy[@]}
      filter_log_details+="  ➡️ グローバルExclude後 残り (最終デプロイ対象): $final_deploy_count 件\n"
    fi
    # --- フィルタリング処理終了 ---
    info "  ➡️ グローバルExclude後 残り (最終デプロイ対象): ${#final_files_to_deploy[@]} 件"

    if ((${#final_files_to_deploy[@]} == 0)); then
        info "フィルタリングの結果、デプロイ対象のファイルがありません。スキップします。"
        local skip_details
        local max_files_to_show=3 # 表示する最大ファイル数を定義
        local changed_files_summary
        local num_changed_files=${#changed_files[@]} # changed_files_rawではなく配列の要素数を使用

        if ((num_changed_files > max_files_to_show)); then
            # changed_files配列から先頭max_files_to_show件を取得
            local first_files_output=""
            for i in $(seq 0 $((max_files_to_show - 1)) ); do
                first_files_output+="${changed_files[$i]}\n"
            done
            changed_files_summary="${first_files_output}...他 ${num_changed_files} 件中 $((num_changed_files - max_files_to_show)) 件のファイルがあります。"
        else
            changed_files_summary="${changed_files_raw}" # 全てのファイルを表示
        fi

        skip_details="**検知された変更ファイル ($original_changed_files_count 件):**\n\`\`\`\n${changed_files_summary}\n\`\`\`\n\n"
        # skip_details+="${filter_log_details}\n" # filter_log_detailsは長すぎるためDiscord通知からは除外。詳細はサーバーログを確認。
        skip_details+="**結果:** デプロイ対象ファイルが0件のため、処理をスキップしました。"

        send_discord_notification "$STATUS_WARNING" \
            "デプロイ スキップ (フィルター)" \
            "$DISCORD_COLOR_WARNING" \
            "$skip_details"
        send_misskey_notification "$STATUS_WARNING" \
            "デプロイ スキップ (フィルター)" \
            "$skip_details"
        return 0
    fi

    info "フィルタリング後のデプロイ対象ファイル (${#final_files_to_deploy[@]} 件):\n$(printf '%s\n' "${final_files_to_deploy[@]}")"

    local commit_message commit_author commit_link repo_name
    commit_message=$($GIT log --format=%B -n 1 "$remote_hash")
    commit_author=$($GIT log --format=%an -n 1 "$remote_hash")
    commit_link="${REPO_URL}/commit/${remote_hash}"
    repo_name=$(echo "$REPO_URL" | sed -E 's|https?://github.com/||' | sed -E 's|\.git$||')

    local files_to_deploy_str
    local num_final_files_to_deploy=${#final_files_to_deploy[@]}
    local max_display_files=3
    if ((${num_final_files_to_deploy} > max_display_files)); then
        local first_files_output=""
        for i in $(seq 0 $((max_display_files - 1)) ); do
            first_files_output+="- ${final_files_to_deploy[$i]}\n"
        done
        files_to_deploy_str="${first_files_output}...他 $((num_final_files_to_deploy - max_display_files)) 件のファイルがあります。"
    else
        files_to_deploy_str=$(printf -- '- %s\n' "${final_files_to_deploy[@]}")
    fi

    local update_detected_details # Use three backticks for code blocks in notifications
    update_detected_details="**コミット情報:**
📦 リポジトリ: $repo_name
🔗 [${remote_hash:0:7}]($commit_link)
👤 作者: $commit_author
📝 メッセージ:
\`\`\`
$commit_message
\`\`\`

**デプロイ対象ファイル (${#final_files_to_deploy[@]} 件):**
\`\`\`
${files_to_deploy_str}
\`\`\`"

    send_discord_notification "$STATUS_WARNING" \
        "更新を検出しデプロイ準備中" \
        "$DISCORD_COLOR_WARNING" \
        "$update_detected_details"
    send_misskey_notification "$STATUS_WARNING" \
        "更新を検出しデプロイ準備中" \
        "$update_detected_details" || true

    info "ブランチ $branch から更新を取得中..."
    if ! $GIT pull origin "$branch" --quiet; then
        handle_error "Git pullに失敗しました。"
    fi

    info "Dockerコンテナのビルドと起動..."
    if $DOCKER compose up -d --build; then
        local deploy_success_details # Use three backticks for code blocks in notifications
        deploy_success_details="**デプロイ成功:**
📦 リポジトリ: $repo_name
🔗 [${remote_hash:0:7}]($commit_link) をデプロイしました。
🐳 Dockerコンテナがビルドされ起動しました。

**デプロイされたファイル:**
\`\`\`
${files_to_deploy_str}
\`\`\`"

        send_discord_notification "$STATUS_SUCCESS" \
            "デプロイ完了 🎉" \
            "$DISCORD_COLOR_SUCCESS" \
            "$deploy_success_details"
        send_misskey_notification "$STATUS_SUCCESS" \
            "デプロイ完了 🎉" \
            "$deploy_success_details"
    else
        handle_error "Docker composeの実行に失敗しました"
    fi

    perform_health_check # ヘルスチェックを実行
}