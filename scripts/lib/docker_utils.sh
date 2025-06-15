#!/bin/bash

# Docker関連のユーティリティ関数群

# shellcheck source=./logging.sh
source "$(dirname "$0")/logging.sh"

# グローバル変数 DOCKER が呼び出し元で設定されていることを期待します。
# また、このスクリプト内の関数が呼ばれる際には、
# カレントディレクトリに docker-compose.yml が存在することを期待します。

# Dockerコンテナをビルドし、デタッチドモードで起動する
# Returns:
#   0: 成功
#   non-zero: 失敗
docker_compose_build_and_up_detached() {
    info "Docker: コンテナをビルドし、デタッチドモードで起動します... ($DOCKER compose up -d --build)"
    if $DOCKER compose up -d --build; then
        info "Docker: ビルドと起動が正常に完了しました。"
        return 0
    else
        # エラーメッセージは docker compose コマンド自体が出力することを期待
        error "Docker: ビルドまたは起動に失敗しました。"
        return 1
    fi
}
