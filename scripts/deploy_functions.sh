#!/bin/bash

# shellcheck source=./lib/logging.sh
source "$SCRIPT_DIR/lib/logging.sh"
# shellcheck source=./lib/notifications.sh
source "$SCRIPT_DIR/lib/notifications.sh"
# shellcheck source=./lib/file_filter.sh
source "$SCRIPT_DIR/lib/file_filter.sh"
# shellcheck source=./lib/health_check.sh
source "$SCRIPT_DIR/lib/health_check.sh"
# shellcheck source=./lib/git_utils.sh
source "$SCRIPT_DIR/lib/git_utils.sh"
# shellcheck source=./lib/docker_utils.sh
source "$SCRIPT_DIR/lib/docker_utils.sh"




deploy() {
    local branch="$1"

    cd "$REPO_DIR" || handle_error "リポジトリディレクトリが見つかりません: $REPO_DIR"

    info "ブランチ $branch のデプロイを開始します"

    local current_hash
    current_hash=$(git_get_local_hash)

    # git_fetch_branch now handles its own errors and calls handle_error internally.
    # It also includes an appropriate info message.
    git_fetch_branch "$branch"

    local remote_hash
    remote_hash=$(git_get_remote_hash "$branch")

    if [[ "$current_hash" == "$remote_hash" ]]; then
        info "更新はありません。デプロイをスキップします。"
        # 必要であれば、更新がなかったことを通知する処理をここに追加できます。
        # 例: send_discord_notification "$STATUS_INFO" "更新なし" "$DISCORD_COLOR_INFO" "インスタンス ${INSTANCE_NAME} は最新の状態です。"
        return 0
    fi

    info "変更されたファイルを確認中 ($current_hash..$remote_hash)..."
    local changed_files_raw
    changed_files_raw=$(git_get_changed_files_between_hashes "$current_hash" "$remote_hash")
    if [[ -z "$changed_files_raw" ]]; then
        info "コミットはありますが、ファイル変更は検出されませんでした。デプロイをスキップします。"
        return 0
    fi

    local changed_files=()
    readarray -t changed_files <<< "$changed_files_raw"

    info "検出された変更ファイル (${#changed_files[@]} 件):\n$changed_files_raw"

    local original_changed_files_count=${#changed_files[@]} # Keep this for notifications
    # filter_log_details is no longer directly populated here; logs are within apply_deploy_filters

    info "**フィルター適用プロセス (外部スクリプト apply_deploy_filters を呼び出し):**"
    local final_files_to_deploy_raw
    # INSTANCE_NAME は deploy.sh など呼び出し元で設定されているグローバル変数を期待
    final_files_to_deploy_raw=$(apply_deploy_filters "$INSTANCE_NAME" "${changed_files[@]}")

    local final_files_to_deploy=()
    if [[ -n "$final_files_to_deploy_raw" ]]; then
        readarray -t final_files_to_deploy <<< "$final_files_to_deploy_raw"
    fi
    info "フィルター適用後の最終デプロイ対象ファイル数: ${#final_files_to_deploy[@]} 件"
    # --- フィルタリング処理は apply_deploy_filters に移行 ---

    if ((${#final_files_to_deploy[@]} == 0)); then
        info "フィルタリングの結果、デプロイ対象のファイルがありません。スキップします。"
        local max_files_to_show=3 # 表示する最大ファイル数を定義
        local num_changed_files=${#changed_files[@]}

        # Discord用メッセージ詳細
        local changed_files_summary_discord
        if ((num_changed_files > max_files_to_show)); then
            local first_files_output_discord=""
            for i in $(seq 0 $((max_files_to_show - 1)) ); do
                first_files_output_discord+="${changed_files[$i]}"$'\n' # Discordは実際の改行
            done
            changed_files_summary_discord="${first_files_output_discord}...他 ${num_changed_files} 件中 $((num_changed_files - max_files_to_show)) 件のファイルがあります。"
        else
            changed_files_summary_discord="${changed_files_raw}" # 全てのファイルを表示 (元々改行区切り)
        fi
        local skip_details_discord="**検知された変更ファイル ($original_changed_files_count 件):**\n\`\`\`\n${changed_files_summary_discord}\n\`\`\`\n\n"
        skip_details_discord+="**結果:** デプロイ対象ファイルが0件のため、処理をスキップしました。"

        # Misskey用メッセージ詳細
        local changed_files_summary_misskey
        if ((num_changed_files > max_files_to_show)); then
            local first_files_output_misskey=""
            for i in $(seq 0 $((max_files_to_show - 1)) ); do
                first_files_output_misskey+="${changed_files[$i]}"$'\n' # Misskeyもシェル内では実際の改行
            done
            # Misskeyのコードブロック内では、シェル変数の改行がそのまま表示される
            changed_files_summary_misskey="検知された変更ファイル (${num_changed_files} 件):
\`\`\`
${first_files_output_misskey}...他 ${num_changed_files} 件中 $((num_changed_files - max_files_to_show)) 件のファイルがあります。
\`\`\`"
        else
            # Misskeyのコードブロック内では、シェル変数の改行がそのまま表示される
            changed_files_summary_misskey="検知された変更ファイル (${num_changed_files} 件):
\`\`\`
${changed_files_raw}
\`\`\`"
        fi
        local skip_details_misskey="結果: デプロイ対象ファイルが0件のため、処理をスキップしました。

${changed_files_summary_misskey}" # Misskey用に整形

        send_discord_notification "$STATUS_WARNING" \
            "デプロイ スキップ (フィルター)" \
            "$DISCORD_COLOR_WARNING" \
            "$skip_details_discord"
        send_misskey_notification "$STATUS_WARNING" \
            "デプロイ スキップ (フィルター)" \
            "$skip_details_misskey"
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

    # git_pull_branch_from_origin now handles its own errors and calls handle_error internally.
    # It also includes an appropriate info message.
    git_pull_branch_from_origin "$branch"

    if docker_compose_build_and_up_detached; then
        info "Dockerコンテナのビルドと起動が正常に完了しました。 (deploy_functions.sh)"
        
        # Discord用ファイルリスト文字列
        local files_to_deploy_str_discord="変更なし"
        if [[ ${#final_files_to_deploy[@]} -gt 0 ]]; then
            files_to_deploy_str_discord=""
            for file_path_discord in "${final_files_to_deploy[@]}"; do
                files_to_deploy_str_discord+="- ${file_path_discord}"$'\n' # Discordは実際の改行
            done
            files_to_deploy_str_discord=${files_to_deploy_str_discord%$'\n'} # 末尾の改行を削除
        fi

        # Misskey用ファイルリスト文字列
        local files_to_deploy_str_misskey="変更なし"
        if [[ ${#final_files_to_deploy[@]} -gt 0 ]]; then
            files_to_deploy_str_misskey=""
            for file_path_misskey in "${final_files_to_deploy[@]}"; do
                files_to_deploy_str_misskey+="- ${file_path_misskey}"$'\n' # Misskeyもシェル内では実際の改行
            done
            files_to_deploy_str_misskey=${files_to_deploy_str_misskey%$'\n'} # 末尾の改行を削除
        fi

        # コミットリンクの取得
        local repo_url
        repo_url=$(get_config_value ".repository.url" "")
        local commit_link_markdown="" # Markdown形式のリンク
        local commit_hash_plain="${remote_hash:-不明}" # ハッシュのみ
        if [[ -n "$repo_url" && -n "$remote_hash" ]]; then
            if [[ "$repo_url" == *.git ]]; then
                repo_url=${repo_url%.git}
            fi
            commit_link_markdown="[${remote_hash:0:7}](${repo_url}/commit/${remote_hash})"
        elif [[ -n "$remote_hash" ]]; then
            commit_link_markdown="${remote_hash:0:7}" # URLがなければ短縮ハッシュ
        fi
        
        # Discord用メッセージ詳細
        local deploy_success_details_discord="**デプロイ成功:**\n"
        deploy_success_details_discord+="インスタンス: $INSTANCE_NAME\n"
        deploy_success_details_discord+="ブランチ: $branch\n"
        if [[ -n "$commit_link_markdown" ]]; then
            deploy_success_details_discord+="コミット: $commit_link_markdown\n"
        else
            deploy_success_details_discord+="コミット: $commit_hash_plain\n"
        fi
        deploy_success_details_discord+="変更ファイル数: ${#final_files_to_deploy[@]}\n"
        deploy_success_details_discord+="\n**デプロイ対象ファイル:**\n"
        deploy_success_details_discord+="\`\`\`\n${files_to_deploy_str_discord}\n\`\`\`"

        # Misskey用メッセージ詳細
        local deploy_success_details_misskey="**デプロイ成功:**
インスタンス: $INSTANCE_NAME
ブランチ: $branch" # シェル内での改行
        if [[ -n "$commit_link_markdown" ]]; then
            deploy_success_details_misskey+=$'\n'"コミット: $commit_link_markdown"
        else
            deploy_success_details_misskey+=$'\n'"コミット: $commit_hash_plain"
        fi
        deploy_success_details_misskey+=$'\n'"変更ファイル数: ${#final_files_to_deploy[@]}"
        deploy_success_details_misskey+=$'\n\n'"**デプロイ対象ファイル:**
\`\`\`
${files_to_deploy_str_misskey}
\`\`\`"

        send_discord_notification "$STATUS_SUCCESS" "デプロイ完了 🎉" "$DISCORD_COLOR_SUCCESS" "$deploy_success_details_discord"
        send_misskey_notification "$STATUS_SUCCESS" "デプロイ完了 🎉" "$deploy_success_details_misskey"

        # ヘルスチェックを実行
        perform_health_check
    else
        # docker_compose_build_and_up_detached 内でエラーログは出力済み
        local deploy_failure_details="インスタンス: $INSTANCE_NAME\nブランチ: $branch\nDocker compose up -d --build に失敗しました。詳細は先行するログを確認してください。"
        send_discord_notification "$STATUS_ERROR" "デプロイ失敗 🚨" "$DISCORD_COLOR_ERROR" "$deploy_failure_details"
        send_misskey_notification "$STATUS_ERROR" "デプロイ失敗 🚨" "$deploy_failure_details"
        # handle_error は docker_utils.sh 側では呼ばない設計なのでここで呼ぶ
        handle_error "Dockerコンテナのビルドまたは起動に失敗しました。詳細は先行するログを確認してください。"
    fi
}