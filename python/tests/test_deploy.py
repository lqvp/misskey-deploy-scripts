"""deploy.py / notifications.py / health.py / log.py のテスト (外部依存はモック)。"""
from __future__ import annotations

from pathlib import Path

import pytest

from misskey_deploy.config import AppConfig, InstanceConfig
from misskey_deploy.deploy import DeployResult, deploy_instance
from misskey_deploy.health import perform_health_check, run_health_check
from misskey_deploy.log import DeployLogger
from misskey_deploy.notifications import Notifier


class FakeResponse:
    def __init__(self, status_code=200, text=""):
        self.status_code = status_code
        self.text = text


class FakeSession:
    """requests.Session のミニモック。get/post の結果をキューで返す。"""

    def __init__(self, responses=None, exceptions=None):
        self.responses = list(responses or [])
        self.exceptions = list(exceptions or [])
        self.requests = []

    def post(self, url, **kwargs):
        self.requests.append(("POST", url))
        if self.exceptions:
            raise self.exceptions.pop(0)
        return self.responses.pop(0)

    def get(self, url, **kwargs):
        self.requests.append(("GET", url))
        if self.exceptions:
            raise self.exceptions.pop(0)
        return self.responses.pop(0)


def _net_error(msg="network error"):
    import requests
    return requests.ConnectionError(msg)


def _make_instance(**overrides) -> InstanceConfig:
    params = dict(
        name="test", repo_dir="/repo", repo_url="https://github.com/x/y",
        branch="main", enabled=True,
    )
    params.update(overrides)
    return InstanceConfig(**params)


def _make_app(instance: InstanceConfig) -> AppConfig:
    return AppConfig(instances={instance.name: instance})


class TestDeployInstance:
    def test_no_update_skips(self, tmp_path, monkeypatch):
        import misskey_deploy.deploy as dep
        inst = _make_instance()
        monkeypatch.setattr(dep, "git_local_hash", lambda r, d: "abc")
        monkeypatch.setattr(dep, "git_remote_hash", lambda r, d, b: "abc")
        result = deploy_instance(_make_app(inst), inst, tmp_path)
        assert result == DeployResult.SKIPPED_NO_UPDATE

    def test_no_target_files_skips(self, tmp_path, monkeypatch):
        import misskey_deploy.deploy as dep
        inst = _make_instance(exclude_paths=["*.md"])
        monkeypatch.setattr(dep, "git_local_hash", lambda r, d: "abc")
        monkeypatch.setattr(dep, "git_remote_hash", lambda r, d, b: "def")
        monkeypatch.setattr(dep, "git_changed_files", lambda r, d, o, n: ["x.md"])
        result = deploy_instance(_make_app(inst), inst, tmp_path)
        assert result == DeployResult.SKIPPED_NO_TARGET

    def test_success_flow(self, tmp_path, monkeypatch):
        import misskey_deploy.deploy as dep
        inst = _make_instance(include_paths=["src/"])
        monkeypatch.setattr(dep, "git_local_hash", lambda r, d: "abc")
        monkeypatch.setattr(dep, "git_remote_hash", lambda r, d, b: "def")
        monkeypatch.setattr(dep, "git_changed_files", lambda r, d, o, n: ["src/a.ts"])
        monkeypatch.setattr(dep, "git_commit_info", lambda r, d, c: ("msg", "author"))
        monkeypatch.setattr(dep, "git_pull", lambda r, d, b: None)
        monkeypatch.setattr(dep, "docker_compose_up_build", lambda r, d: None)
        result = deploy_instance(_make_app(inst), inst, tmp_path)
        assert result == DeployResult.SUCCESS
        # ログファイルが logs/<name>/ に作成されている
        log = tmp_path / "logs" / "test" / "test-deploy.log"
        assert log.exists()

    def test_dry_run_does_not_send_notifications(self, tmp_path, monkeypatch):
        """dry-run 中は例外が発生しても実通知を送らない。"""
        import misskey_deploy.deploy as dep

        def boom(runner, repo_dir):
            raise RuntimeError("fetch failed")

        inst = _make_instance()
        monkeypatch.setattr(dep, "git_local_hash", boom)
        sent = []
        monkeypatch.setattr(
            Notifier, "send_discord",
            lambda self, m, d="": sent.append(m) or True, raising=True)
        result = deploy_instance(_make_app(inst), inst, tmp_path, dry_run=True)
        assert result == DeployResult.FAILURE
        assert sent == []  # 実Notifierには届かない
