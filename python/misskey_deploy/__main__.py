"""CLI エントリポイント。

使用方法: python3 -m misskey_deploy <インスタンス名> [--dry-run] [--debug] [--config PATH]
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

from .config import ConfigError, load_config
from .deploy import DeployResult, deploy_instance


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Misskey deployment script (Python)")
    parser.add_argument("instance", help="deploy_config.yaml で定義されたインスタンス名")
    parser.add_argument("--config", default=None, help="設定YAMLのパス (デフォルト: <project>/configs/deploy_config.yaml)")
    parser.add_argument("--dry-run", action="store_true", help="git pull / docker compose / 通知を実行せずに動作確認")
    parser.add_argument("--debug", action="store_true", help="デバッグログを有効化")
    args = parser.parse_args(argv)

    project_root = Path(__file__).resolve().parent.parent
    config_path = Path(args.config) if args.config else project_root / "configs" / "deploy_config.yaml"

    try:
        app = load_config(config_path)
    except ConfigError as e:
        print(f"エラー: {e}", file=sys.stderr)
        return 1

    instance = app.instances.get(args.instance)
    if instance is None:
        print(f"エラー: インスタンス '{args.instance}' は設定ファイルに存在しないか無効です。", file=sys.stderr)
        return 1

    result = deploy_instance(app, instance, project_root, dry_run=args.dry_run, debug=args.debug)
    if result == DeployResult.FAILURE:
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
