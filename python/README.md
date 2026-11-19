# Misskey Deployment Scripts (Python)

Bash版 (`misskey-deploy-scripts`) の Python リライト。設定YAML・CLI引数に互換性があります。

## 機能

- **同一設定ファイル**: 旧 `scripts/configs/deploy_config.yaml` をそのまま `configs/deploy_config.yaml` として使用可能
- **差分検出デプロイ**: git fetch → 差分ファイル → include/exclude フィルタ → `docker compose up -d --build`
- **ヘルスチェック**: リトライ付きのHTTPヘルスチェック
- **通知**: Discord Webhook / Misskey ノート（リトライ付き）
- **ログローテーション**: サイズベース（`RotatingFileHandler`）
- **dry-run モード**: `--dry-run` で pull / docker / 通知を実行せず動作確認
- **依存の削減**: yq / jq / bc / curl が不要（必要なのは python3, git, docker のみ）

## セットアップ

```bash
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt

cp configs/deploy_config.yaml.example configs/deploy_config.yaml
# configs/deploy_config.yaml を編集
```

## 使用方法

```bash
# venv がある場合は deploy.sh ラッパーが自動で使用する
./deploy.sh <インスタンス名>

# 直接実行
.venv/bin/python -m misskey_deploy <インスタンス名> [--dry-run] [--debug] [--config PATH]
```

## cron 設定例

```cron
*/5 * * * * /path/to/misskey-deploy-scripts-python/deploy.sh misskey_live >> /path/to/misskey-deploy-scripts-python/logs/cron.log 2>&1
```

## 環境変数オーバーライド

旧版と同じ `CONFIG_OVERRIDE_*` 形式。例:

```bash
export CONFIG_OVERRIDE_INSTANCES_INDEX_0_REPO_DIR="/new/path"
```

## テスト

```bash
python3 -m venv .venv && .venv/bin/pip install -r requirements.txt pytest
.venv/bin/python -m pytest tests/ -q
```

## Bash版からの移行

[MIGRATION.md](MIGRATION.md) を参照してください。

## ライセンス

MIT License（旧リポジトリに準拠）
