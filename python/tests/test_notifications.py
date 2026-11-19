"""Notifier・ヘルスチェック・ロガーのテスト。"""
from __future__ import annotations

import logging

from test_deploy import FakeResponse, FakeSession, _make_instance, _net_error

from misskey_deploy.health import perform_health_check, run_health_check
from misskey_deploy.log import DeployLogger
from misskey_deploy.notifications import Notifier


class TestNotifier:
    def _notifier(self, **kw):
        return Notifier(
            discord_webhook_url="https://discord.example/hook",
            misskey_host="https://misskey.example",
            misskey_token="TOKEN",
            instance_name="test", **kw,
        )

    def test_discord_success(self):
        sess = FakeSession(responses=[FakeResponse(204)])
        ok = self._notifier(session=sess).send_discord("msg")
        assert ok
        assert sess.requests[0][1] == "https://discord.example/hook"

    def test_discord_retries_on_error(self):
        sess = FakeSession(exceptions=[_net_error("net1"), _net_error("net2")],
                           responses=[FakeResponse(204)])
        # retry_delay で sleep しないため time.sleep を短絡
        import misskey_deploy.notifications as n
        orig_sleep = n.time.sleep
        n.time.sleep = lambda s: None
        try:
            ok = self._notifier(session=sess).send_discord("msg")
        finally:
            n.time.sleep = orig_sleep
        assert ok
        assert len(sess.requests) == 3  # 2失敗 + 1成功

    def test_misskey_success(self):
        sess = FakeSession(responses=[FakeResponse(200)])
        ok = self._notifier(session=sess).send_misskey("msg")
        assert ok
        assert sess.requests[0][1] == "https://misskey.example/api/notes/create"

    def test_misskey_skipped_without_token(self):
        notifier = Notifier(discord_webhook_url="", misskey_host="", misskey_token="")
        assert notifier.send_misskey("msg") is True


class TestHealthCheck:
    def test_success(self):
        sess = FakeSession(responses=[FakeResponse(200, "ok")])
        ok, status = perform_health_check("http://x", 5, 200, session=sess)
        assert ok and status == "200"

    def test_content_mismatch_fails(self):
        sess = FakeSession(responses=[FakeResponse(200, "unrelated")])
        ok, _ = perform_health_check("http://x", 5, 200, "expected", session=sess)
        assert not ok

    def test_retries_then_success(self):
        sess = FakeSession(responses=[FakeResponse(502), FakeResponse(502), FakeResponse(200)])
        import misskey_deploy.health as h
        orig_sleep = h.time.sleep
        h.time.sleep = lambda s: None
        try:
            ok, _ = perform_health_check("http://x", 5, 200, retries=2, session=sess)
        finally:
            h.time.sleep = orig_sleep
        assert ok
        assert len(sess.requests) == 3

    def test_run_health_check_disabled(self):
        inst = _make_instance()
        logger = _FakeLogger()
        run_health_check(inst, _NoopNotifier(), logger)
        assert any("無効" in m for m in logger.infos)


class _FakeLogger:
    def __init__(self):
        self.infos = []

    def info(self, msg):
        self.infos.append(msg)


class _NoopNotifier:
    def send_discord(self, *a, **kw): return True
    def send_misskey(self, *a, **kw): return True


class TestDeployLogger:
    def test_creates_log_file(self, tmp_path):
        log_file = tmp_path / "logs" / "inst" / "inst-deploy.log"
        logger = DeployLogger("inst", log_file, rotation_enabled=False)
        logger.info("hello")
        for h in list(logger.logger.handlers):
            h.close()
            logger.logger.removeHandler(h)
        assert log_file.exists()
        assert "hello" in log_file.read_text(encoding="utf-8")

    def test_rotation(self, tmp_path):
        log_file = tmp_path / "inst.log"
        logger = DeployLogger("inst", log_file, rotation_enabled=True,
                              max_bytes=200, backup_count=2)
        for i in range(50):
            logger.info(f"line {i} " + "x" * 50)
        for h in list(logger.logger.handlers):
            h.close()
            logger.logger.removeHandler(h)
        assert log_file.exists()
        assert (tmp_path / "inst.log.1").exists()
