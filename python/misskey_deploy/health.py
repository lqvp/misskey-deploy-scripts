"""HTTPヘルスチェック。"""
from __future__ import annotations

import time

import requests

from .config import InstanceConfig


def perform_health_check(url: str, timeout_seconds: int, expected_status: int,
                         expected_contains: str = "", *, logger=None,
                         retries: int = 0, retry_delay_seconds: int = 5,
                         session: requests.Session | None = None) -> tuple[bool, str]:
    """HTTPヘルスチェック。リトライ付きで実行し、(成功か, ステータス) を返す。"""
    sess = session or requests.Session()
    for attempt in range(1, retries + 2):
        try:
            response = sess.get(url, timeout=timeout_seconds)
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


def run_health_check(instance: InstanceConfig, notifier, logger,
                     *, session: requests.Session | None = None) -> None:
    """デプロイ後のヘルスチェックを実行し、結果に応じて通知する。"""
    hc = instance.health_check
    if not hc.enabled or not hc.url:
        logger.info("ヘルスチェックは無効またはURL未設定のためスキップします。")
        return
    ok, _ = perform_health_check(
        hc.url, hc.timeout_seconds, hc.expected_status_code,
        hc.expected_response_contains, logger=logger,
        retries=hc.retries, retry_delay_seconds=hc.retry_delay_seconds,
        session=session,
    )
    if ok:
        notifier.send_discord(f"✅ ヘルスチェック完了 ({instance.name})")
    else:
        notifier.send_discord(f"🚨 ヘルスチェック失敗 ({instance.name})")
        notifier.send_misskey(f"🚨 ヘルスチェック失敗 ({instance.name})")
