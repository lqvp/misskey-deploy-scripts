#!/bin/bash

# scripts/config_parser.sh

_sanitize_key_for_env() {
    local key="$1"
    # Remove leading dot, then uppercase, then replace dots and hyphens with underscores
    # Also remove array-like parts like '[*]' or '[]'
    echo "$key" | sed -e 's/^\.//' -e 's/\[.*\]//g' | awk '{print toupper($0)}' | sed 's/[.-]/_/g'
}


# yqコマンドのパス。環境変数 YQ_PATH があればそれを使用し、なければ 'yq' を使用。
# deploy_config.yaml の command_paths.yq で指定されていればそちらを優先。
YQ_COMMAND="${YQ_PATH:-yq}"

# 設定ファイルパス (グローバル変数として deploy.sh から設定されることを期待)
# MAIN_CONFIG_FILE="scripts/configs/deploy_config.yaml"

# 初期化関数: yqコマンドの存在確認と、設定ファイルからのyqパス読み込み
initialize_parser() {
    # 設定ファイルからyqのパスを取得試行
    local yq_path_in_config
    if [[ -f "$MAIN_CONFIG_FILE" ]]; then
        # yq自身でyqのパスを読むのは鶏卵なので、grepとsedで簡易的に読む
        yq_path_in_config=$(grep -E "^\s*yq:" "$MAIN_CONFIG_FILE" | sed -E 's/^\s*yq:\s*//' | tr -d '"' | tr -d "'")
        if [[ -n "$yq_path_in_config" ]]; then
            YQ_COMMAND="$yq_path_in_config"
        fi
    fi

    if ! command -v "$YQ_COMMAND" &> /dev/null; then
        echo "エラー: YAMLパーサー '$YQ_COMMAND' が見つかりません。" >&2
        echo "yqをインストールするか、有効なパスを deploy_config.yaml の command_paths.yq または環境変数 YQ_PATH で指定してください。" >&2
        echo "インストール方法 (例): sudo wget https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 -O /usr/local/bin/yq && sudo chmod +x /usr/local/bin/yq" >&2
        return 1
    fi
    return 0
}

# 指定されたキーの値をYAMLファイルから取得する
# $1: YAMLファイルのパス
# $2: yqで指定するキー (例: ".global_settings.discord_webhook_url")
# $3: (オプション) 値が見つからない場合のデフォルト値
get_config_value() {
    local file_path="$1"
    local key="$2"
    local default_value="${3:-}"
    local value

    if [[ ! -f "$file_path" ]]; then
        echo "エラー: 設定ファイルが見つかりません: $file_path" >&2
        # デフォルト値が指定されていればそれを返す
        if [[ -n "$default_value" ]]; then
            echo "$default_value"
            return 0
        fi
        return 1
    fi

    # yqで値を取得。nullや空文字の場合も考慮
    value=$("$YQ_COMMAND" eval "$key" "$file_path")

    # yqの出力が 'null' 文字列または空の場合、値なしとみなす
    if [[ "$value" == "null" ]] || [[ -z "$value" ]]; then
        if [[ -n "$default_value" ]]; then
            echo "$default_value"
        else
            # 値がなくデフォルトもない場合は空文字を返す (エラーにはしない)
            echo ""
        fi
    else
        echo "$value"
    fi
    return 0
}

# 指定されたインスタンス名に合致するインスタンス設定のインデックスを取得する
# $1: YAMLファイルのパス
# $2: インスタンス名
get_instance_index() {
    local file_path="$1"
    local instance_name="$2"
    local index

    index=$("$YQ_COMMAND" eval '.instances | to_entries | .[] | select(.value.name == "'$instance_name'") | .key' "$file_path")

    if [[ "$index" == "null" ]] || [[ -z "$index" ]]; then
        echo "エラー: インスタンス '$instance_name' の設定が見つかりません。" >&2
        return 1
    fi
    echo "$index"
    return 0
}

# グローバル設定値を取得するショートカット関数
# $1: グローバル設定のキー (例: ".deploy_filters.exclude_paths")
# $2: (オプション) デフォルト値
get_global_setting() {
    local yaml_key_suffix="$1" # e.g., ".discord_webhook_url"
    local default_value="${2:-}"
    local sanitized_key_name
    local env_var_name

    sanitized_key_name=$(_sanitize_key_for_env "$yaml_key_suffix")
    env_var_name="DEPLOY_GLOBAL_${sanitized_key_name}"

    # Check if environment variable is set and has a non-empty value
    if [[ -n "${!env_var_name-}" && -n "${!env_var_name}" ]]; then
        echo "${!env_var_name}"
        return 0
    fi

    get_config_value "$MAIN_CONFIG_FILE" ".global_settings$yaml_key_suffix" "$default_value"
}

# 特定インスタンスの設定値を取得するショートカット関数
# $1: インスタンス名
# $2: インスタンス設定のキー (例: ".repo_dir")
# $3: (オプション) デフォルト値
get_instance_setting() {
    local instance_name="$1"
    local yaml_key_suffix="$2" # e.g., ".repo_dir"
    local default_value="${3:-}"
    local sanitized_key_name
    local upper_instance_name
    local env_var_name
    local instance_index
    local value

    sanitized_key_name=$(_sanitize_key_for_env "$yaml_key_suffix")
    upper_instance_name=$(echo "$instance_name" | awk '{print toupper($0)}')
    env_var_name="DEPLOY_INSTANCE_${upper_instance_name}_${sanitized_key_name}"

    # Check if environment variable is set and has a non-empty value
    if [[ -n "${!env_var_name-}" && -n "${!env_var_name}" ]]; then
        echo "${!env_var_name}"
        return 0
    fi

    if ! instance_index=$(get_instance_index "$MAIN_CONFIG_FILE" "$instance_name"); then
        if [[ -n "$default_value" ]]; then
            echo "$default_value"
            return 0
        fi
        return 1
    fi

    # Store the result of get_config_value in 'value' before echoing
    value=$(get_config_value "$MAIN_CONFIG_FILE" ".instances[$instance_index]$yaml_key_suffix" "$default_value")
    echo "$value"
}

# 特定インスタンスの設定値を取得。もしインスタンスになければグローバル設定から取得。
# $1: インスタンス名
# $2: インスタンス設定のキー (例: ".discord_webhook_url")
# $3: グローバル設定のキー (例: ".discord_webhook_url")
# $4: (オプション) デフォルト値
get_instance_or_global_setting() {
    local instance_name="$1"
    local instance_key="$2"
    local global_key="$3"
    local default_value="${4:-}"
    local value

    # まずインスタンス固有の設定を試みる
    value=$(get_instance_setting "$instance_name" "$instance_key")

    # インスタンス固有設定が空またはnullの場合、グローバル設定を試みる
    if [[ -z "$value" ]] || [[ "$value" == "null" ]]; then
        value=$(get_global_setting "$global_key")
    fi

    # グローバル設定も空またはnullの場合、デフォルト値を返す
    if [[ -z "$value" ]] || [[ "$value" == "null" ]]; then
        echo "$default_value"
    else
        echo "$value"
    fi
}

# 配列形式の設定値を取得する (例: exclude_paths)
# $1: YAMLファイルのパス
# $2: yqで指定するキー (例: ".global_settings.deploy_filters.exclude_paths")
# 返り値: 配列の各要素を改行区切りで出力
get_config_array() {
    local file_path="$1"
    local key="${2:-}" # $2が未設定の場合、空文字列をkeyに設定
    local result

    result=$("$YQ_COMMAND" eval "$key | .[]" "$file_path")
    if [[ "$result" == "null" ]] || [[ -z "$result" ]]; then
        echo "" # 空を返す
    else
        echo "$result" # 各要素が改行区切りで出力される
    fi
}

# グローバル設定から配列を取得 (環境変数オーバーライド対応)
# $1: グローバル設定のキーサフィックス (例: ".deploy_filters.exclude_paths")
# 環境変数名は DEPLOY_GLOBAL_DEPLOY_FILTERS_EXCLUDE_PATHS (カンマ区切り)
get_global_array_setting() {
    local yaml_key_suffix="$1"
    local sanitized_key_name
    local env_var_name
    local env_value_csv

    sanitized_key_name=$(_sanitize_key_for_env "$yaml_key_suffix")
    env_var_name="DEPLOY_GLOBAL_${sanitized_key_name}"

    if [[ -n "${!env_var_name-}" && -n "${!env_var_name}" ]]; then
        env_value_csv="${!env_var_name}"
        echo "$env_value_csv" | tr ',' '\n'
        return 0
    fi
    get_config_array "$MAIN_CONFIG_FILE" ".global_settings$yaml_key_suffix"
}

# インスタンス設定から配列を取得 (環境変数オーバーライド対応)
# $1: インスタンス名
# $2: インスタンス設定のキーサフィックス (例: ".deploy_filters.exclude_paths")
# 環境変数名は DEPLOY_INSTANCE_INSTANCENAME_DEPLOY_FILTERS_EXCLUDE_PATHS (カンマ区切り)
get_instance_array_setting() {
    local instance_name="$1"
    local yaml_key_suffix="$2"
    local sanitized_key_name
    local upper_instance_name
    local env_var_name
    local env_value_csv
    local instance_index

    sanitized_key_name=$(_sanitize_key_for_env "$yaml_key_suffix")
    upper_instance_name=$(echo "$instance_name" | awk '{print toupper($0)}')
    env_var_name="DEPLOY_INSTANCE_${upper_instance_name}_${sanitized_key_name}"

    if [[ -n "${!env_var_name-}" && -n "${!env_var_name}" ]]; then
        env_value_csv="${!env_var_name}"
        echo "$env_value_csv" | tr ',' '\n'
        return 0
    fi

    if ! instance_index=$(get_instance_index "$MAIN_CONFIG_FILE" "$instance_name"); then
        # インスタンスが見つからない場合、空を返す (エラーはget_instance_indexで出力済みの想定)
        echo ""
        return 1 # 呼び出し元でエラーハンドリングが必要な場合があるため
    fi
    get_config_array "$MAIN_CONFIG_FILE" ".instances[$instance_index]$yaml_key_suffix"
}

# -----------------------------------------------------------------------------
# Function: initialize_theme_settings
# Description:
#   Loads theme settings (emojis, Discord colors) from the YAML configuration
#   file. If a setting is not found in YAML, it uses the default value
#   defined in config.sh (e.g., DEFAULT_STATUS_SUCCESS).
#   This function should be called after config.sh and config_parser.sh
#   have been sourced, and before these theme variables are used.
# Globals:
#   Reads:
#     - DEFAULT_STATUS_SUCCESS, DEFAULT_STATUS_ERROR, ... (from config.sh)
#     - DEFAULT_DISCORD_COLOR_SUCCESS, ... (from config.sh)
#     - MAIN_CONFIG_FILE (path to deploy_config.yaml, used by get_config_value)
#   Writes:
#     - STATUS_SUCCESS, STATUS_ERROR, ...
#     - DISCORD_COLOR_SUCCESS, DISCORD_COLOR_ERROR, ...
# Usage:
#   initialize_theme_settings
# -----------------------------------------------------------------------------
initialize_theme_settings() {
    # Ensure config.sh defaults are available
    # (This function assumes config.sh has been sourced)

    info "テーマ設定を初期化しています..."

    # Status Emojis
    # These variables are expected to be declared in config.sh (e.g., STATUS_SUCCESS="")
    STATUS_SUCCESS=$(get_config_value "$MAIN_CONFIG_FILE" ".global_settings.theme.emojis.success" "$DEFAULT_STATUS_SUCCESS")
    STATUS_ERROR=$(get_config_value "$MAIN_CONFIG_FILE" ".global_settings.theme.emojis.error" "$DEFAULT_STATUS_ERROR")
    STATUS_WARNING=$(get_config_value "$MAIN_CONFIG_FILE" ".global_settings.theme.emojis.warning" "$DEFAULT_STATUS_WARNING")
    STATUS_INFO=$(get_config_value "$MAIN_CONFIG_FILE" ".global_settings.theme.emojis.info" "$DEFAULT_STATUS_INFO")

    # Discord Notification Colors
    # These variables are expected to be declared in config.sh (e.g., DISCORD_COLOR_SUCCESS="")
    DISCORD_COLOR_SUCCESS=$(get_config_value "$MAIN_CONFIG_FILE" ".global_settings.theme.discord_colors.success" "$DEFAULT_DISCORD_COLOR_SUCCESS")
    DISCORD_COLOR_ERROR=$(get_config_value "$MAIN_CONFIG_FILE" ".global_settings.theme.discord_colors.error" "$DEFAULT_DISCORD_COLOR_ERROR")
    DISCORD_COLOR_WARNING=$(get_config_value "$MAIN_CONFIG_FILE" ".global_settings.theme.discord_colors.warning" "$DEFAULT_DISCORD_COLOR_WARNING")
    DISCORD_COLOR_INFO=$(get_config_value "$MAIN_CONFIG_FILE" ".global_settings.theme.discord_colors.info" "$DEFAULT_DISCORD_COLOR_INFO")

    debug "テーマ設定完了:"
    debug "  STATUS_SUCCESS: $STATUS_SUCCESS"
    debug "  STATUS_ERROR: $STATUS_ERROR"
    debug "  STATUS_WARNING: $STATUS_WARNING"
    debug "  STATUS_INFO: $STATUS_INFO"
    debug "  DISCORD_COLOR_SUCCESS: $DISCORD_COLOR_SUCCESS"
    debug "  DISCORD_COLOR_ERROR: $DISCORD_COLOR_ERROR"
    debug "  DISCORD_COLOR_WARNING: $DISCORD_COLOR_WARNING"
    debug "  DISCORD_COLOR_INFO: $DISCORD_COLOR_INFO"
}
