"""ログ出力とサイズベースのログローテーション。"""
from __future__ import annotations

import logging
from logging.handlers import RotatingFileHandler
from pathlib import Path


class DeployLogger:
    """インスタンスごとのロガー。RotatingFileHandler でローテーション。"""

    def __init__(
        self,
        instance_name: str,
        log_file: Path,
        *,
        debug: bool = False,
        rotation_enabled: bool = True,
        max_bytes: int = 10 * 1024 * 1024,
        backup_count: int = 5,
    ):
        level = logging.DEBUG if debug else logging.INFO
        fmt = logging.Formatter(f"%(asctime)s [{instance_name}] [%(levelname)s] %(message)s")

        self.logger = logging.getLogger(f"misskey_deploy.{instance_name}")
        self.logger.setLevel(level)
        self.logger.propagate = False
        # 既存ハンドラはファイルディスクリプタを閉じてから破棄する (毎分実行されるため)
        for handler in list(self.logger.handlers):
            handler.close()
            self.logger.removeHandler(handler)

        log_file.parent.mkdir(parents=True, exist_ok=True)
        if rotation_enabled:
            file_handler: logging.Handler = RotatingFileHandler(
                log_file, maxBytes=max(1, max_bytes),
                backupCount=max(1, backup_count), encoding="utf-8",
            )
        else:
            file_handler = RotatingFileHandler(log_file, encoding="utf-8")
        file_handler.setLevel(level)
        file_handler.setFormatter(fmt)
        self.logger.addHandler(file_handler)

        console = logging.StreamHandler()
        console.setLevel(level)
        console.setFormatter(fmt)
        self.logger.addHandler(console)

    def debug(self, msg: str) -> None:
        self.logger.debug(msg)

    def info(self, msg: str) -> None:
        self.logger.info(msg)

    def warn(self, msg: str) -> None:
        self.logger.warning(msg)

    def error(self, msg: str) -> None:
        self.logger.error(msg)
