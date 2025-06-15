#!/bin/bash

# Git関連のユーティリティ関数群

# shellcheck source=./logging.sh
source "$(dirname "$0")/logging.sh"

# グローバル変数 GIT および REPO_DIR が呼び出し元で設定されていることを期待します。
# また、このスクリプト内の関数が呼ばれる際には、
# カレントディレクトリが $REPO_DIR になっていることを期待します。

# 指定されたブランチの最新情報をリモートから取得する
# Args:
#   $1: ブランチ名
git_fetch_branch() {
    local branch_name="$1"
    if [[ -z "$branch_name" ]]; then
        error "git_fetch_branch: ブランチ名が指定されていません。"
        return 1
    fi
    info "Git: ブランチ '$branch_name' の最新情報を取得中..."
    if ! $GIT fetch origin "$branch_name" --quiet; then
        handle_error "Git fetch (origin $branch_name) に失敗しました。"
        return 1 # handle_error は通常 exit するが、念のため
    fi
    return 0
}

# 現在のローカルリポジトリのHEADコミットハッシュを取得する
git_get_local_hash() {
    local local_hash
    local_hash=$($GIT rev-parse HEAD 2>/dev/null)
    if [[ -z "$local_hash" ]]; then
        error "Git: ローカルのコミットハッシュの取得に失敗しました。"
        return 1
    fi
    echo "$local_hash"
    return 0
}

# 指定されたブランチのリモートのコミットハッシュを取得する
# Args:
#   $1: ブランチ名
git_get_remote_hash() {
    local branch_name="$1"
    if [[ -z "$branch_name" ]]; then
        error "git_get_remote_hash: ブランチ名が指定されていません。"
        return 1
    fi
    local remote_hash
    remote_hash=$($GIT rev-parse "origin/$branch_name" 2>/dev/null)
    if [[ -z "$remote_hash" ]]; then
        error "Git: リモートブランチ 'origin/$branch_name' のコミットハッシュの取得に失敗しました。"
        return 1
    fi
    echo "$remote_hash"
    return 0
}

# 2つのコミットハッシュ間の変更ファイルリストを取得する
# Args:
#   $1: 古いコミットハッシュ (例: current_hash)
#   $2: 新しいコミットハッシュ (例: remote_hash)
git_get_changed_files_between_hashes() {
    local old_hash="$1"
    local new_hash="$2"
    if [[ -z "$old_hash" || -z "$new_hash" ]]; then
        error "git_get_changed_files_between_hashes: コミットハッシュが指定されていません。"
        return 1
    fi
    
    local changed_files_raw
    changed_files_raw=$($GIT diff --name-only "$old_hash" "$new_hash" 2>/dev/null)
    # diff コマンドはエラー時に空文字列を返すことがあるので、$? も確認した方が良いかもしれないが、
    # 現状の deploy_functions.sh の動作に合わせ、空の場合も許容する。
    # エラーメッセージは $GIT の stderr に依存する。
    echo "$changed_files_raw"
    return 0
}

# 指定されたブランチをリモートの origin からプルする
# Args:
#   $1: ブランチ名
git_pull_branch_from_origin() {
    local branch_name="$1"
    if [[ -z "$branch_name" ]]; then
        error "git_pull_branch_from_origin: ブランチ名が指定されていません。"
        return 1
    fi
    info "Git: ブランチ '$branch_name' を origin からプルしています..."
    if ! $GIT pull origin "$branch_name" --quiet; then
        handle_error "Git pull (origin $branch_name) に失敗しました。"
        return 1 # handle_error は通常 exit するが、念のため
    fi
    info "Git pull が正常に完了しました。"
    return 0
}
