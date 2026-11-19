"""Git・Docker 操作ユーティリティ。"""
from __future__ import annotations

import subprocess
from dataclasses import dataclass


class CommandError(Exception):
    """外部コマンドの実行失敗。"""


@dataclass
class Runner:
    """dry_run 対応のコマンド実行ラッパー。"""

    dry_run: bool = False

    def run(self, args: list[str], *, cwd: str | None = None, check: bool = True,
            dry: bool = False) -> subprocess.CompletedProcess:
        """コマンドを実行し、失敗時は CommandError を投げる。

        dry=True のコマンドは dry_run 中でも実際に実行する (参照系コマンド用)。
        """
        if self.dry_run and not dry:
            print(f"[dry-run] {' '.join(args)}" + (f" (cwd={cwd})" if cwd else ""))
            return subprocess.CompletedProcess(args, 0, "", "")
        try:
            result = subprocess.run(
                args, cwd=cwd, capture_output=True, text=True, timeout=3600
            )
        except (OSError, subprocess.TimeoutExpired) as e:
            raise CommandError(f"コマンド実行に失敗しました: {' '.join(args)}: {e}") from e
        if check and result.returncode != 0:
            raise CommandError(
                f"コマンドが失敗しました ({result.returncode}): {' '.join(args)}\n{result.stderr.strip()}"
            )
        return result


def git_local_hash(runner: Runner, repo_dir: str) -> str:
    return runner.run(["git", "rev-parse", "HEAD"], cwd=repo_dir, dry=True).stdout.strip()


def git_remote_hash(runner: Runner, repo_dir: str, branch: str) -> str:
    runner.run(["git", "fetch", "origin", branch, "--quiet"], cwd=repo_dir, dry=True)
    return runner.run(["git", "rev-parse", f"origin/{branch}"], cwd=repo_dir, dry=True).stdout.strip()


def git_changed_files(runner: Runner, repo_dir: str, old: str, new: str) -> list[str]:
    out = runner.run(["git", "diff", "--name-only", old, new], cwd=repo_dir, dry=True).stdout
    return [line for line in out.splitlines() if line.strip()]


def git_pull(runner: Runner, repo_dir: str, branch: str) -> None:
    runner.run(["git", "pull", "origin", branch, "--quiet"], cwd=repo_dir)


def git_commit_info(runner: Runner, repo_dir: str, commit: str) -> tuple[str, str]:
    """(コミットメッセージ, 作者名) を返す。"""
    fmt = runner.run(
        ["git", "log", "--format=%B%n---AUTHOR---%n%an", "-n", "1", commit], cwd=repo_dir, dry=True
    ).stdout
    message, _, author = fmt.partition("---AUTHOR---\n")
    return message.strip(), author.strip()


def docker_compose_up_build(runner: Runner, repo_dir: str) -> None:
    runner.run(["docker", "compose", "up", "-d", "--build"], cwd=repo_dir)
