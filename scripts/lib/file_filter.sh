#!/bin/bash

# shellcheck source=../config_parser.sh
source "$(dirname "$0")/../config_parser.sh" # SCRIPT_DIRからの相対パスを想定

# apply_deploy_filters
# Arguments:
#   $1: INSTANCE_NAME (文字列)
#   $@: (残り全て) 変更されたファイルのリスト (配列として渡されることを期待するが、実際は個別の引数として渡ってくる)
# Globals:
#   MAIN_CONFIG_FILE (config_parser.sh が利用)
# Outputs:
#   フィルタリング後のファイルリストを標準出力に改行区切りで出力
apply_deploy_filters() {
    local instance_name="$1"
    shift # インスタンス名を引数リストから削除
    local changed_files=("$@") # 残りの引数を配列として取得

    # グローバル設定とインスタンス固有設定を config_parser.sh の関数を使って取得
    # 注意: get_global_array_setting や get_instance_array_setting は改行区切りの文字列を返すため、配列に変換する必要がある

    local global_include_paths_str
    global_include_paths_str=$(get_global_array_setting ".deploy_filters.include_paths")
    local -a GLOBAL_INCLUDE_PATHS
    readarray -t GLOBAL_INCLUDE_PATHS <<< "$global_include_paths_str"

    local instance_include_paths_str
    instance_include_paths_str=$(get_instance_array_setting "$instance_name" ".deploy_filters.include_paths")
    local -a INSTANCE_INCLUDE_PATHS
    readarray -t INSTANCE_INCLUDE_PATHS <<< "$instance_include_paths_str"

    local global_exclude_paths_str
    global_exclude_paths_str=$(get_global_array_setting ".deploy_filters.exclude_paths")
    local -a GLOBAL_EXCLUDE_PATHS
    readarray -t GLOBAL_EXCLUDE_PATHS <<< "$global_exclude_paths_str"

    local instance_exclude_paths_str
    instance_exclude_paths_str=$(get_instance_array_setting "$instance_name" ".deploy_filters.exclude_paths")
    local -a INSTANCE_EXCLUDE_PATHS
    readarray -t INSTANCE_EXCLUDE_PATHS <<< "$instance_exclude_paths_str"

    # --- deploy_functions.sh から移植したフィルタリングロジック --- 
    local files_after_include_filter=()
    local files_after_instance_exclude=()
    local final_files_to_deploy=()

    # 1. Includeフィルターを適用 (インスタンス固有設定を優先、なければグローバル設定を参照)
    local -a EFFECTIVE_INCLUDE_PATHS
    if ((${#INSTANCE_INCLUDE_PATHS[@]} > 0)); then
        EFFECTIVE_INCLUDE_PATHS=("${INSTANCE_INCLUDE_PATHS[@]}")
    elif ((${#GLOBAL_INCLUDE_PATHS[@]} > 0)); then
        EFFECTIVE_INCLUDE_PATHS=("${GLOBAL_INCLUDE_PATHS[@]}")
    fi

    if ((${#EFFECTIVE_INCLUDE_PATHS[@]} > 0)); then
        for file in "${changed_files[@]}"; do
            local matched_include=false
            for pattern in "${EFFECTIVE_INCLUDE_PATHS[@]}"; do
                if [[ "$file" == $pattern* || "$file" == $pattern ]]; then
                    matched_include=true
                    break
                fi
            done
            if $matched_include; then
                files_after_include_filter+=("$file")
            fi
        done
    else
        files_after_include_filter=("${changed_files[@]}")
    fi

    # 2. インスタンス Exclude フィルター
    if ((${#INSTANCE_EXCLUDE_PATHS[@]} > 0)); then
        for file in "${files_after_include_filter[@]}"; do
            local matched_exclude=false
            for pattern in "${INSTANCE_EXCLUDE_PATHS[@]}"; do
                if [[ "$file" == $pattern* || "$file" == $pattern ]]; then # 前方一致も考慮
                    matched_exclude=true
                    break
                fi
            done
            if ! $matched_exclude; then
                files_after_instance_exclude+=("$file")
            fi
        done
    else
        files_after_instance_exclude=("${files_after_include_filter[@]}")
    fi

    # 3. グローバル Exclude フィルター
    if ((${#GLOBAL_EXCLUDE_PATHS[@]} > 0)); then
        for file in "${files_after_instance_exclude[@]}"; do
            local matched_exclude=false
            for pattern in "${GLOBAL_EXCLUDE_PATHS[@]}"; do
                if [[ "$file" == $pattern* || "$file" == $pattern ]]; then # 前方一致も考慮
                    matched_exclude=true
                    break
                fi
            done
            if ! $matched_exclude; then
                final_files_to_deploy+=("$file")
            fi
        done
    else
        final_files_to_deploy=("${files_after_instance_exclude[@]}")
    fi
    # --- フィルタリングロジックここまで ---

    # フィルタリング後のファイルリストを標準出力へ
    for file in "${final_files_to_deploy[@]}"; do
        echo "$file"
    done
}
