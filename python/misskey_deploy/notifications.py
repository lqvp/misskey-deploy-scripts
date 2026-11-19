"""Discord / Misskey 通知とヘルスチェック。"""
from __future__ import annotations

import time

import requests


class Notifier:
    """Discord / Misskey への通知送信 (リトライ付き)。"""

    def __init__(self, discord_webhook_url: str, misskey_host: str, misskey_token: str,
                 misskey_visibility: str = "public", misskey_local_only: bool = False,
                 instance_name: str = "", logger=None, timeout: int = 10):
        self.discord_webhook_url = discord_webhook_url
        self.misskey_host = misskey_host.rstrip("/")
        self.misskey_token = misskey_token
        self.misskey_visibility = misskey_visibility
        self.misskey_local_only = misskey_local_only
        self.instance_name = instance_name
        self.logger = logger
        self.timeout = timeout

    def _log(self, level: str, msg: str) -> None:
        if self.logger is not None:
            getattr(self.logger, level)(msg)

    def _post_with_retries(self, url: str, payload: dict, *, expected: int = 204,
                            max_retries: int = 3, retry_delay: int = 5) -> bool:
        for attempt in range(1, max_retries + 1):
            try:
                response = requests.post(url, json=payload, timeout=self.timeout)
                if response.status_code == expected:
                    return True
                self._log("warn", f"通知送信失敗 (試行 {attempt}/{max_retries}, HTTP {response.status_code}): {url}")
            except requests.RequestException as e:
                self._log("warn", f"通知送信エラー (試行 {attempt}/{max_retries}): {e}")
            if attempt < max_retries:
                time.sleep(retry_delay)
        return False

    def send_discord(self, message: str, details: str = "") -> bool:
        """Discord webhook に Embed を送信する。"""
        if not self.discord_webhook_url:
            self._log("debug", "Discord Webhook URLが未設定のため通知をスキップします。")
            return True
        embed = {"title": "Deployment Notification", "description": message,
                 "fields": [{"name": f"Instance: {self.instance_name}", "value": " "}] if self.instance_name else []}
        if details:
            embed["fields"].append({"name": "Details", "value": details[:1024]})
        payload = {"embeds": [embed]}
        return self._post_with_retries(self.discord_webhook_url, payload)

    def send_misskey(self, message: str, details: str = "") -> bool:
        """Misskey API (notes/create) でノートを投稿する。"""
        if not self.misskey_host or not self.misskey_token:
            self._log("warn", "Misskeyホストまたはトークンが未設定のため通知をスキップします。")
            return True
        text = f"**Deployment Notification ({self.instance_name})**\n{message}"
        if details:
            text += f"\n\n{details}"
        payload = {
            "text": text,
            "visibility": self.misskey_visibility,
            "localOnly": self.misskey_local_only,
            "i": self.misskey_token,
        }
        return self._post_with_retries(
            f"{self.misskey_host}/api/notes/create", payload, expected=200
        )


def perform_health_check(url: str, timeout_seconds: int, expected_status: int,
                         expected_contains: str = "", *, logger=None,
                         retries: int = 0, retry_delay_seconds: int = 5) -> tuple[bool, str]:
    """HTTPヘルスチェック。リトライ付きで実行し、(成功か, 詳細メッセージ) を返す。"""
    for attempt in range(1, retries + 2):
        try:
            response = requests.get(url, timeout=timeout_seconds)
            if response.status_code == expected_status:
                if expected_contains and expected_contains not in response.text:
                    if logger:
                        logger.warn(f"ヘルスチェック失敗 (試行 {attempt}): レスポンス内容が一致しません。")
                else:
                    return True, str(response.status_code)
            elif logger:
                logger.warn(
                    f"ヘルスチェック失敗 (試行 {attempt}): HTTP {response.status_code} (期待: {expected_status})"
                )
        except requests.RequestException as e:
            if logger:
                logger.warn(f"ヘルスチェック失敗 (試行 {attempt}): {e}")
        if attempt <= retries:
            time.sleep(retry_delay_seconds)
    return False, ""
