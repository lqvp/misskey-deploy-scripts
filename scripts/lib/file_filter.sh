#!/bin/bash

# shellcheck source=../config_parser.sh
SCRIPT_DIR_LIB=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR_LIB/../config_parser.sh"

# グローバル変数としてフィルター設定を保持
declare -a GLOBAL_INCLUDE_PATHS
declare -a GLOBAL_EXCLUDE_PATHS
declare -a INSTANCE_INCLUDE_PATHS
declare -a INSTANCE_EXCLUDE_PATHS

# load_deploy_filter_settings
# Arguments:
#   $1: INSTANCE_NAME (文字列)
# Globals:
#   MAIN_CONFIG_FILE (config_parser.sh が利用)
#   GLOBAL_INCLUDE_PATHS, GLOBAL_EXCLUDE_PATHS, INSTANCE_INCLUDE_PATHS, INSTANCE_EXCLUDE_PATHS (これらをセットする)
# Outputs:
#   なし
load_deploy_filter_settings() {
    local instance_name="$1"
    log_debug "フィルター設定読み込み開始 (${instance_name})"

    # get_config_array はスペース区切りの文字列を配列として返すように config_parser.sh で定義されている想定
    # もし get_config_array が改行区切りの文字列を返す場合は、readarray の使い方が変わる

    GLOBAL_INCLUDE_PATHS=($(get_config_array ".global_settings.deploy_filter.include_paths"))
    log_debug "  グローバル インクルードパス (${#GLOBAL_INCLUDE_PATHS[@]}件): ${GLOBAL_INCLUDE_PATHS[*]}"
    GLOBAL_EXCLUDE_PATHS=($(get_config_array ".global_settings.deploy_filter.exclude_paths"))
    log_debug "  グローバル エクスクルードパス (${#GLOBAL_EXCLUDE_PATHS[@]}件): ${GLOBAL_EXCLUDE_PATHS[*]}"

    INSTANCE_INCLUDE_PATHS=($(get_config_array ".instances.${instance_name}.deploy_filter.include_paths"))
    log_debug "  インスタンス (${instance_name}) インクルードパス (${#INSTANCE_INCLUDE_PATHS[@]}件): ${INSTANCE_INCLUDE_PATHS[*]}"
    INSTANCE_EXCLUDE_PATHS=($(get_config_array ".instances.${instance_name}.deploy_filter.exclude_paths"))
    log_debug "  インスタンス (${instance_name}) エクスクルードパス (${#INSTANCE_EXCLUDE_PATHS[@]}件): ${INSTANCE_EXCLUDE_PATHS[*]}"
    log_debug "フィルター設定読み込み完了 (${instance_name})"
}

# apply_deploy_filters
# Arguments:
#   $1: INSTANCE_NAME (文字列)
#   $@: (残り全て) 変更されたファイルのリスト
# Globals:
#   GLOBAL_INCLUDE_PATHS, GLOBAL_EXCLUDE_PATHS, INSTANCE_INCLUDE_PATHS, INSTANCE_EXCLUDE_PATHS (load_deploy_filter_settings によってセットされる)
# Outputs:
#   フィルタリング後のファイルリストを標準出力に改行区切りで出力
apply_deploy_filters() {
    local instance_name="$1"
    shift
    local -a changed_files=("$@")
    local -a final_deploys=()

    log_debug "--- apply_deploy_filters 開始 (${instance_name}) ---"
    log_debug "入力ファイル数: ${#changed_files[@]}"
    load_deploy_filter_settings "$instance_name"

    for file in "${changed_files[@]}"; do
        log_debug "処理中のファイル: '$file'"
        local deploy_this_file=false
        local matched_path_type=""
        local matched_pattern=""

        # Step 1: インクルードルールの評価 (インスタンス優先)
        # インスタンス固有のインクルードルールがあるか？
        if [[ ${#INSTANCE_INCLUDE_PATHS[@]} -gt 0 ]]; then
            matched_path_type="インスタンスインクルード"
            for pattern in "${INSTANCE_INCLUDE_PATHS[@]}"; do
                if [[ "$file" == "$pattern"* || "$file" == "$pattern" ]]; then
                    deploy_this_file=true
                    matched_pattern="$pattern"
                    log_debug "  -> '$file' は ${matched_path_type} パターン '$matched_pattern' にマッチ。デプロイ候補。"
                    break
                fi
            done
            if ! $deploy_this_file; then
                 log_debug "  -> '$file' はいずれの ${matched_path_type} パターンにもマッチせず。"
            fi
        # グローバルなインクルードルールがあるか？ (インスタンスインクルードがない場合)
        elif [[ ${#GLOBAL_INCLUDE_PATHS[@]} -gt 0 ]]; then
            matched_path_type="グローバルインクルード"
            for pattern in "${GLOBAL_INCLUDE_PATHS[@]}"; do
                if [[ "$file" == "$pattern"* || "$file" == "$pattern" ]]; then
                    deploy_this_file=true
                    matched_pattern="$pattern"
                    log_debug "  -> '$file' は ${matched_path_type} パターン '$matched_pattern' にマッチ。デプロイ候補。"
                    break
                fi
            done
            if ! $deploy_this_file; then
                 log_debug "  -> '$file' はいずれの ${matched_path_type} パターンにもマッチせず。"
            fi
        # インクルードルールが全くない場合は、デフォルトで全ファイルが対象
        else
            deploy_this_file=true
            log_debug "  -> インクルードルールが存在しないため、'$file' はデフォルトでデプロイ候補。"
        fi

        # Step 2: エクスクルードルールの評価 (インクルード候補のファイルに対してのみ)
        if $deploy_this_file; then
            local excluded_by_instance=false
            # インスタンス固有のエクスクルードルール
            if [[ ${#INSTANCE_EXCLUDE_PATHS[@]} -gt 0 ]]; then
                for pattern in "${INSTANCE_EXCLUDE_PATHS[@]}"; do
                    if [[ "$file" == "$pattern"* || "$file" == "$pattern" ]]; then
                        deploy_this_file=false # 除外する
                        excluded_by_instance=true
                        log_debug "  -> '$file' はインスタンスエクスクルードパターン '$pattern' にマッチ。デプロイから除外。"
                        break
                    fi
                done
            fi

            # グローバルなエクスクルードルール (インスタンスルールで除外されなかった場合のみ評価)
            if $deploy_this_file && ! $excluded_by_instance && [[ ${#GLOBAL_EXCLUDE_PATHS[@]} -gt 0 ]]; then
                for pattern in "${GLOBAL_EXCLUDE_PATHS[@]}"; do
                    if [[ "$file" == "$pattern"* || "$file" == "$pattern" ]]; then
                        deploy_this_file=false # 除外する
                        log_debug "  -> '$file' はグローバルエクスクルードパターン '$pattern' にマッチ。デプロイから除外。"
                        break
                    fi
                done
            fi
        else # インクルード候補でなかったファイル
            log_debug "  -> '$file' はインクルード候補でなかったため、エクスクルード評価スキップ。"
        fi

        # 最終的な判断
        if $deploy_this_file; then
            log_debug "最終判断: '$file' をデプロイ対象リストに追加します。"
            final_deploys+=("$file")
        else
            log_debug "最終判断: '$file' はデプロイ対象リストから除外されました。"
        fi
    done

    log_debug "--- apply_deploy_filters 完了 (${instance_name}) ---"
    if [[ ${#final_deploys[@]} -eq 0 ]]; then
        log_debug "最終結果: フィルター適用後、デプロイ対象ファイルはありません。"
    else
        log_debug "最終的なデプロイ対象ファイル (${#final_deploys[@]} 件):"
        for f_deploy in "${final_deploys[@]}"; do
            log_debug "  - ${f_deploy}"
        done
    fi

    printf '%s\n' "${final_deploys[@]}"
}
