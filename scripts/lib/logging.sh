#!/bin/bash

# logging.sh

# LOG_FILE, INSTANCE_NAME, DEBUG_MODE は呼び出し元スクリプトで設定されていることを想定
# 未設定の場合のフォールバック値 (主に直接実行時のテスト用)
LOG_FILE=${LOG_FILE:-/tmp/deploy_default.log}
INSTANCE_NAME=${INSTANCE_NAME:-DEFAULT_INSTANCE}
DEBUG_MODE=${DEBUG_MODE:-false}

# config_parser.sh の get_global_setting が使えるように、事前に source されているか、
# もしくはこのスクリプトが deploy.sh から呼ばれることで関数が利用可能になっている想定。
# 念のため、関数存在チェックを行う。
if ! command -v get_global_setting &> /dev/null; then
    # deploy.sh の中で CONFIG_PARSER_SCRIPT が source されるので、
    # logging.sh が deploy.sh より先に source される場合はこのエラーが出る可能性がある。
    # ただし、現状の deploy.sh の構成では問題ないはず。
    echo "WARN: get_global_setting function not found. Log rotation might not work if called outside deploy.sh context." >&2
fi

rotate_log_if_needed() {
    # get_global_setting が使えるか再確認
    if ! command -v get_global_setting &> /dev/null; then
        return 0 # 関数がなければローテーションは行わない
    fi

    local rotation_enabled
    rotation_enabled=$(get_global_setting ".log_rotation.enabled" "false")

    if [[ "$rotation_enabled" != "true" ]]; then
        return 0
    fi

    local max_size_mb max_files
    max_size_mb=$(get_global_setting ".log_rotation.max_size_mb" "0")
    max_files=$(get_global_setting ".log_rotation.max_files" "0")

    # MB単位なのでバイトに変換。bcコマンドが必要。なければローテーションしない。
    if ! command -v bc &> /dev/null; then
        echo "WARN: 'bc' command not found. Cannot perform log rotation by size." >&2
        return 1
    fi
    local max_size_bytes
    max_size_bytes=$(echo "$max_size_mb * 1024 * 1024" | bc)

    if [[ "$max_size_bytes" -le 0 ]] || [[ "$max_files" -le 0 ]]; then
        return 0
    fi

    if [[ ! -f "$LOG_FILE" ]]; then
        return 0
    fi

    local current_size_bytes
    current_size_bytes=$(stat -c%s "$LOG_FILE" 2>/dev/null || echo 0)

    if [[ "$current_size_bytes" -gt "$max_size_bytes" ]]; then
        # ローテーション実行
        # 1. 最も古いログファイルを削除 (例: log.5 があれば削除)
        if [[ -f "${LOG_FILE}.${max_files}" ]]; then
            rm -f "${LOG_FILE}.${max_files}"
        fi

        # 2. 既存の古いログファイルをリネーム (例: log.4 -> log.5, log.3 -> log.4, ...)
        # 降順でループすることで、上書きを防ぐ
        local i
        for ((i = max_files - 1; i >= 1; i--)); do
            if [[ -f "${LOG_FILE}.${i}" ]]; then
                mv -f "${LOG_FILE}.${i}" "${LOG_FILE}.$((i + 1))"
            fi
        done

        # 3. 現在のログファイルを .1 にリネーム
        if [[ -f "$LOG_FILE" ]]; then
            mv -f "$LOG_FILE" "${LOG_FILE}.1"
        fi
        # 新しいログファイルは、この後の log_base での書き込み時に自動作成される
        echo "[$ (date '+%Y-%m-%d %H:%M:%S')] [${INSTANCE_NAME}] [INFO] Log rotated: ${LOG_FILE} was moved to ${LOG_FILE}.1" >> "${LOG_FILE}.1" # ローテーションしたファイルに記録
    fi
}

log_base() {
    local level="$1"
    local message="$2"

    # ログローテーションチェックを最初に行う
    rotate_log_if_needed

    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    # ログファイルが指定されていれば、そこに追記
    if [[ -n "$LOG_FILE" ]]; then
        # ログディレクトリの存在確認と作成 (万が一消えていた場合など)
        local log_dir
        log_dir=$(dirname "$LOG_FILE")
        if [[ ! -d "$log_dir" ]]; then
            mkdir -p "$log_dir"
        fi
        echo "[$timestamp] [$INSTANCE_NAME] [$level] $message" >>"$LOG_FILE"
    else
    # LOG_FILEが空の場合は標準エラーに出力 (設定ミスなどの検知用)
        echo "[$timestamp] [$INSTANCE_NAME] [$level] $message" >&2
    fi
}

info() { log_base "INFO" "$1"; }
error() { log_base "ERROR" "$1"; } # handle_error からも呼ばれる
warn() { log_base "WARN" "$1"; }
debug() {
    if [[ "$DEBUG_MODE" == "true" ]]; then
        log_base "DEBUG" "$1"
    fi
}