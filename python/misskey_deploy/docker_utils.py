"""Docker操作ユーティリティ。"""
from __future__ import annotations

from .git_utils import Runner


def docker_compose_up_build(runner: Runner, repo_dir: str) -> None:
    """docker compose up -d --build を実行する。"""
    runner.run(["docker", "compose", "up", "-d", "--build"], cwd=repo_dir)
