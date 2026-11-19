"""デプロイのメインフロー。"""
from __future__ import annotations

from pathlib import Path

from .config import AppConfig, InstanceConfig
from .docker_utils import docker_compose_up_build
from .filters import apply_filters
from .git_utils import Runner, git_changed_files, git_commit_info, git_local_hash, \
    git_pull, git_remote_hash
from .health import run_health_check
from .log import DeployLogger
from .notifications import Notifier


class DeployResult:
    SKIPPED_NO_UPDATE = "no_update"
    SKIPPED_NO_TARGET = "no_target"
    SUCCESS = "success"
    FAILURE = "failure"


class _DryRunNotifier:
    """dry-run 時に通知送信を抑止するラッパー。"""

    def __init__(self, base: Notifier, logger):
        self._base = base
        self._logger = logger

    def send_discord(self, message: str, details: str = "") -> bool:
        self._logger.info(f"[dry-run] Discord通知をスキップ: {message}")
        return True

    def send_misskey(self, message: str, details: str = "") -> bool:
        self._logger.info(f"[dry-run] Misskey通知をスキップ: {message}")
        return True


def deploy_instance(app: AppConfig, instance: InstanceConfig, project_root: Path,
                    *, dry_run: bool = False, debug: bool = False) -> str:
    """1インスタンスのデプロイを実行し、DeployResult の定数を返す。"""
    log_dir = project_root / "logs" / instance.name
    log_file = log_dir / f"{instance.name}-deploy.log"
    logger = DeployLogger(
        instance.name, log_file, debug=debug,
        rotation_enabled=app.log_rotation.get("enabled", False),
        max_bytes=int(app.log_rotation.get("max_size_mb", 10)) * 1024 * 1024,
        backup_count=int(app.log_rotation.get("max_files", 5)),
    )
    runner = Runner(dry_run=dry_run)
    notifier = Notifier(
        discord_webhook_url=instance.discord_webhook_url,
        misskey_host=instance.misskey_notification.host,
        misskey_token=instance.misskey_notification.token,
        misskey_visibility=instance.misskey_notification.visibility,
        misskey_local_only=instance.misskey_notification.local_only,
        instance_name=instance.name, logger=logger,
    )
    # dry-run 時は例外経路を含めすべての通知を抑止する
    effective_notifier = _DryRunNotifier(notifier, logger) if dry_run else notifier

    logger.info(f"======= デプロイ開始: {instance.name} =======")
    try:
        return _deploy(app, instance, runner, logger, effective_notifier, dry_run)
    except Exception as e:
        logger.error(f"デプロイ中にエラーが発生しました: {e}")
        effective_notifier.send_discord(f"❌ デプロイメントエラー ({instance.name})", f"```\n{e}\n```")
        effective_notifier.send_misskey(f"❌ デプロイメントエラー ({instance.name})", f"```\n{e}\n```")
        return DeployResult.FAILURE


def _deploy(app: AppConfig, instance: InstanceConfig, runner: Runner,
            logger: DeployLogger, notifier, dry_run: bool) -> str:
    current_hash = git_local_hash(runner, instance.repo_dir)
    remote_hash = git_remote_hash(runner, instance.repo_dir, instance.branch)

    if current_hash == remote_hash:
        logger.info("更新はありません。デプロイをスキップします。")
        return DeployResult.SKIPPED_NO_UPDATE

    changed_files = git_changed_files(runner, instance.repo_dir, current_hash, remote_hash)
    if not changed_files:
        logger.info("コミットはありますが、ファイル変更は検出されませんでした。スキップします。")
        return DeployResult.SKIPPED_NO_UPDATE

    deploy_files = apply_filters(
        changed_files,
        instance.include_paths or app.global_include_paths,
        instance.exclude_paths + app.global_exclude_paths,
    )
    if not deploy_files:
        logger.info("フィルタリングの結果、デプロイ対象のファイルがありません。スキップします。")
        return DeployResult.SKIPPED_NO_TARGET

    message, author = git_commit_info(runner, instance.repo_dir, remote_hash)
    summary = f"コミット {remote_hash[:7]} (by {author}):\n{message}\n対象 {len(deploy_files)} 件"
    notifier.send_discord(f"⚠️ 更新を検出: {instance.name}", summary)
    notifier.send_misskey(f"⚠️ 更新を検出: {instance.name}", summary)

    git_pull(runner, instance.repo_dir, instance.branch)
    docker_compose_up_build(runner, instance.repo_dir)
    logger.info("Dockerコンテナのビルドと起動が完了しました。")

    notifier.send_discord(f"✅ デプロイ完了 🎉 ({instance.name})", summary)
    notifier.send_misskey(f"✅ デプロイ完了 🎉 ({instance.name})", summary)

    run_health_check(instance, notifier, logger)
    logger.info(f"======= デプロイ完了: {instance.name} =======")
    return DeployResult.SUCCESS
