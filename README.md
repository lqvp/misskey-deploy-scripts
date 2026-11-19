# Misskey Deployment Scripts

Automated deployment scripts for Misskey instances, featuring multi-instance management via a unified YAML configuration, health checks, log rotation, and Discord/Misskey notifications.

## 🐍 Python版 (推奨 / Recommended)

現在のメインは `python/` 以下のPython実装です。設定YAML・CLI呼び出しはBash版と互換性があります。

```bash
cd python
python3 -m venv .venv && .venv/bin/pip install -r requirements.txt
cp configs/deploy_config.yaml.example configs/deploy_config.yaml
./deploy.sh <instance_name> --dry-run   # 動作確認
./deploy.sh <instance_name>             # 実行
```

**特徴**:

- **依存の削減**: 必要なのは `python3` + `git` + `docker`（yq / jq / bc / curl 不要）
- **同一設定ファイル**: 既存の `deploy_config.yaml` をそのまま使用可能
- **dry-run モード**: git pull / docker compose / 通知を実行せずに動作確認
- **テスト同梱**: pytest による自動テスト (31件)
- 差分検出デプロイ、include/exclude フィルタ、リトライ付きヘルスチェック、Discord/Misskey通知、ログローテーションはBash版から全て継承

詳細は [python/README.md](python/README.md) を参照してください。

## 📜 Bash版 (レガシー / Legacy)

`scripts/` 以下のBash実装はメンテナンスモードです。新規セットアップにはPython版を利用してください。

- 実行には `git`, `docker`, `curl`, `jq`, `yq`, `bc` が必要です
- 設定ファイルは `scripts/configs/deploy_config.yaml` です
- Bash版からPython版への移行手順は [python/MIGRATION.md](python/MIGRATION.md) を参照してください

機能の詳細 (Bash版):

- **Unified YAML Configuration**: Manage all instance settings in a single `deploy_config.yaml` file.
- **Environment Variable Overrides**: Override any YAML configuration value using environment variables (`CONFIG_OVERRIDE_*`).
- **Selective Deployment**: Filter deployments based on changed paths in the Git repository.
- **Automated Health Checks**: Post-deployment health checks with retries.
- **Built-in Log Rotation**: Size-based log rotation.
- **ShellCheck Integration**: CI workflow includes `shellcheck`.
- **Theme Customization**: Customize notification emojis and Discord colors.

## Requirements

| | Python版 | Bash版 |
|---|---|---|
| 実行環境 | Python 3.9+ | Bash 4.0+ |
| 外部コマンド | git, docker | git, docker, curl, jq, yq, bc |
| Pythonパッケージ | PyYAML, requests | ― |

## Bash版からの移行

[python/MIGRATION.md](python/MIGRATION.md) にcron切替・ロールバック手順をまとめています。

## License

MIT License
