# 移行手順: Bash版 → Python版

現行の `misskey-deploy-scripts`（Bash版）から `misskey-deploy-scripts-python`（Python版）への移行手順です。
設定YAML（`deploy_config.yaml`）のスキーマとCLI呼び出し方（`deploy.sh <インスタンス名>`）は互換性があるため、設定ファイルの書き換えは原則不要です。

## 前提

| 項目 | Bash版 | Python版 |
|------|--------|----------|
| 必要コマンド | git, docker, curl, jq, yq, bc | git, docker, python3 (3.9+), pip |
| Pythonパッケージ | ― | PyYAML, requests |
| 設定ファイル | `scripts/configs/deploy_config.yaml` | `configs/deploy_config.yaml`（スキーマ同一） |
| 実行方法 | `./scripts/deploy.sh <name>` | `./deploy.sh <name>`（ラッパー） または `python3 -m misskey_deploy <name>` |

## 1. 事前確認

```bash
# 現行のcron設定を控えておく（あとで切り替えに使う）
crontab -l > ~/crontab_backup.txt

# 現在の設定ファイルをバックアップ
cp -r /path/to/misskey-deploy-scripts/scripts/configs ~/deploy_config_backup
```

## 2. Python版のセットアップ

```bash
cd /path/to
git clone <このリポジトリ> misskey-deploy-scripts-python
# または既存リポジトリ内に python/ として配置した場合はそれをコピー

cd misskey-deploy-scripts-python

# venv を作成（推奨: システムPythonを汚さない）
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt

# 設定ファイルを流用（スキーマ同一のためそのまま使える）
mkdir -p configs
cp /path/to/misskey-deploy-scripts/scripts/configs/deploy_config.yaml configs/
```

## 3. 動作確認（本番に影響なし）

```bash
# dry-run: git fetch まで実行し、pull / docker compose / 通知は行わない
./deploy.sh <インスタンス名> --dry-run --debug
```

- 「更新はありません」「フィルタリングの結果、デプロイ対象のファイルがありません」等のログが出ることを確認
- ログは旧版と同じく `logs/<インスタンス名>/<インスタンス名>-deploy.log` に出力される

## 4. 切り替え

cron のエントリを新版に差し替えます。

```bash
crontab -e
# 旧:
# */5 * * * * /path/to/misskey-deploy-scripts/scripts/deploy.sh misskey_live >> .../logs/cron.log 2>&1
# 新:
*/5 * * * * /path/to/misskey-deploy-scripts-python/deploy.sh misskey_live >> /path/to/misskey-deploy-scripts-python/logs/cron.log 2>&1
```

初回は手動実行してデプロイと通知が正常に完了することを確認します。

```bash
./deploy.sh misskey_live
```

## 5. 旧版の退役

1. 〜24時間程度運用し、新版で問題がないことを確認
2. 旧ディレクトリはアーカイブとして保管（`mv misskey-deploy-scripts misskey-deploy-scripts.bash.bak`）
3. 問題があれば crontab を旧パスに戻すだけで即ロールバック可能（旧版は削除していないため）

## 互換性の注意点

- **環境変数オーバーライド** (`CONFIG_OVERRIDE_*`) は同一形式（`_INDEX_<n>_` による配列指定を含む）で利用可能。ただしPython版では設定内に存在しないキーを指定した場合、エラーになります（タイポ検知の強化）
- 旧Bash版の `lib/file_filter.sh` には `deploy_filters`（複数形）と `deploy_filter`（単数形）のパスキーの不整合バグがありました。Python版は両方を読み込みます（`deploy_filters` を優先）
- 通知の本文フォーマットは簡素化されています（ Discord Embed / Misskey ノートの送信先・リトライ回数は同等）
- `yq` / `jq` / `bc` / `curl` は不要になります（PyYAML・requests が代替）

## ロールバック手順（要約）

1. `crontab -e` で旧スクリプトのパスに戻す
2. 旧設定は変更していないため、`misskey-deploy-scripts/` がそのまま動作する
