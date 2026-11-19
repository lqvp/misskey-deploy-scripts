"""YAML設定の読み込み・環境変数オーバーライド・検証。

既存の scripts/configs/deploy_config.yaml と同一スキーマを読み込む。
"""
from __future__ import annotations

import copy
import os
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

import yaml

DEFAULTS: dict[str, Any] = {
    "theme": {
        "emojis": {"success": "✅", "error": "❌", "warning": "⚠️", "info": "ℹ️"},
        "discord_colors": {
            "success": 3066993,
            "error": 15158332,
            "warning": 15105570,
            "info": 3447003,
        },
    },
    "log_rotation": {"enabled": False, "max_size_mb": 10, "max_files": 5},
    "misskey_notification": {
        "enabled": False,
        "host": "",
        "token": "",
        "visibility": "public",
        "local_only": False,
    },
    "health_check": {
        "enabled": False,
        "url": "",
        "timeout_seconds": 10,
        "retries": 3,
        "retry_delay_seconds": 5,
        "expected_status_code": 200,
        "expected_response_contains": "",
    },
}


class ConfigError(Exception):
    """設定ファイルの読み込み・検証エラー。"""


def _deep_merge(base: dict, override: dict) -> dict:
    """override の値で base を再帰的に上書きする。"""
    merged = copy.deepcopy(base)
    for key, value in override.items():
        if isinstance(value, dict) and isinstance(merged.get(key), dict):
            merged[key] = _deep_merge(merged[key], value)
        else:
            merged[key] = value
    return merged


def _set_override(node: Any, tokens: list, value: Any) -> None:
    """トークン列を既存キーに最長一致で辿り、葉に値をセットする。"""
    if not tokens:
        return
    if isinstance(node, list) and isinstance(tokens[0], int):
        index = tokens[0]
        if index >= len(node):
            raise ConfigError(f"配列インデックスが範囲外です: {index}")
        if len(tokens) == 1:
            node[index] = value
            return
        _set_override(node[index], tokens[1:], value)
        return
    # 先頭から連続する文字列トークンに対し最長一致するキーを探す
    # (例: global_settings_log_rotation_max_size_mb
    #  -> global_settings / log_rotation / max_size_mb)
    max_n = 0
    while max_n < len(tokens) and isinstance(tokens[max_n], str):
        max_n += 1
    for n in range(max_n, 0, -1):
        key = "_".join(tokens[:n])
        if isinstance(node, dict) and key in node:
            if n == len(tokens):
                node[key] = value
            else:
                _set_override(node[key], tokens[n:], value)
            return
    # 既存キーに一致しない場合はタイポの可能性が高いのでエラーにする
    raise ConfigError(
        f"環境変数オーバーライドのパスが設定内のキーに一致しません: {'_'.join(map(str, tokens))}"
    )


def _apply_env_overrides(config: dict, env: dict[str, str] | None = None) -> dict:
    """CONFIG_OVERRIDE_ 接頭辞の環境変数で設定を上書きする。

    例: CONFIG_OVERRIDE_GLOBAL_SETTINGS_LOG_ROTATION_MAX_SIZE_MB=20 は
    global_settings.log_rotation.max_size_mb を上書きする。
    インスタンス配列は _INDEX_<n>_ で指定する。
    """
    env = env if env is not None else os.environ
    for key, value in env.items():
        if not key.startswith("CONFIG_OVERRIDE_"):
            continue
        tokens = key[len("CONFIG_OVERRIDE_"):].split("_")
        # _INDEX_<n>_ を配列インデックスに変換
        parsed: list = []
        i = 0
        while i < len(tokens):
            if tokens[i] == "INDEX":
                if i + 1 >= len(tokens) or not tokens[i + 1].isdigit():
                    raise ConfigError("環境変数のパス形式が不正です: INDEX の後に数字が必要です")
                parsed.append(int(tokens[i + 1]))
                i += 2
                continue
            parsed.append(tokens[i].lower())
            i += 1
        _set_override(config, parsed, yaml.safe_load(value))
    return config


def _to_bool(value: Any) -> bool:
    if isinstance(value, bool):
        return value
    if isinstance(value, str):
        return value.strip().lower() == "true"
    return bool(value)


@dataclass
class HealthCheckConfig:
    enabled: bool = False
    url: str = ""
    timeout_seconds: int = 10
    retries: int = 3
    retry_delay_seconds: int = 5
    expected_status_code: int = 200
    expected_response_contains: str = ""


@dataclass
class MisskeyNotificationConfig:
    enabled: bool = False
    host: str = ""
    token: str = ""
    visibility: str = "public"
    local_only: bool = False


@dataclass
class InstanceConfig:
    name: str
    enabled: bool = True
    repo_dir: str = ""
    repo_url: str = ""
    branch: str = ""
    discord_webhook_url: str = ""
    misskey_notification: MisskeyNotificationConfig = field(default_factory=MisskeyNotificationConfig)
    health_check: HealthCheckConfig = field(default_factory=HealthCheckConfig)
    include_paths: list[str] = field(default_factory=list)
    exclude_paths: list[str] = field(default_factory=list)

    def validate(self) -> None:
        if not self.repo_dir or not self.repo_url or not self.branch:
            raise ConfigError(
                f"インスタンス '{self.name}' の必須設定 (repo_dir, repo_url, branch) が不足しています。"
            )


@dataclass
class AppConfig:
    instances: dict[str, InstanceConfig] = field(default_factory=dict)
    global_include_paths: list[str] = field(default_factory=list)
    global_exclude_paths: list[str] = field(default_factory=list)
    discord_webhook_url: str = ""
    misskey_notification: MisskeyNotificationConfig = field(default_factory=MisskeyNotificationConfig)
    log_rotation: dict[str, Any] = field(default_factory=lambda: dict(DEFAULTS["log_rotation"]))
    theme: dict[str, Any] = field(default_factory=lambda: dict(DEFAULTS["theme"]))


def _get_filters(raw: dict, key: str) -> list[str]:
    """deploy_filters / deploy_filter (旧バグ互換) の両方を見る。"""
    section = raw.get("deploy_filters") or raw.get("deploy_filter") or {}
    return list(section.get(key) or [])


def _load_instance(raw: dict) -> InstanceConfig:
    hc = {**DEFAULTS["health_check"], **(raw.get("health_check") or {})}
    mn = {**DEFAULTS["misskey_notification"], **(raw.get("misskey_notification") or {})}
    return InstanceConfig(
        name=str(raw["name"]),
        enabled=_to_bool(raw.get("enabled", True)),
        repo_dir=str(raw.get("repo_dir", "")),
        repo_url=str(raw.get("repo_url", "")),
        branch=str(raw.get("branch", "")),
        discord_webhook_url=str(raw.get("discord_webhook_url", "")),
        misskey_notification=MisskeyNotificationConfig(
            enabled=_to_bool(mn["enabled"]),
            host=str(mn["host"]),
            token=str(mn["token"]),
            visibility=str(mn["visibility"]),
            local_only=_to_bool(mn["local_only"]),
        ),
        health_check=HealthCheckConfig(
            enabled=_to_bool(hc["enabled"]),
            url=str(hc["url"]),
            timeout_seconds=int(hc["timeout_seconds"]),
            retries=int(hc["retries"]),
            retry_delay_seconds=int(hc["retry_delay_seconds"]),
            expected_status_code=int(hc["expected_status_code"]),
            expected_response_contains=str(hc["expected_response_contains"]),
        ),
        include_paths=_get_filters(raw, "include_paths"),
        exclude_paths=_get_filters(raw, "exclude_paths"),
    )


def load_config(config_path: str | Path, env: dict[str, str] | None = None) -> AppConfig:
    """YAML設定ファイルを読み込み AppConfig を返す。"""
    path = Path(config_path)
    if not path.is_file():
        raise ConfigError(f"設定ファイルが見つかりません: {path}")
    try:
        raw = yaml.safe_load(path.read_text(encoding="utf-8")) or {}
    except yaml.YAMLError as e:
        raise ConfigError(f"YAMLの解析に失敗しました: {path}: {e}") from e
    if not isinstance(raw, dict):
        raise ConfigError(f"設定ファイルのルートがマップではありません: {path}")

    raw = _apply_env_overrides(raw, env)

    app = AppConfig()
    g = raw.get("global_settings") or {}
    app.discord_webhook_url = str(g.get("discord_webhook_url", ""))
    mn = {**DEFAULTS["misskey_notification"], **(g.get("misskey_notification") or {})}
    app.misskey_notification = MisskeyNotificationConfig(
        enabled=_to_bool(mn["enabled"]),
        host=str(mn["host"]),
        token=str(mn["token"]),
        visibility=str(mn["visibility"]),
        local_only=_to_bool(mn["local_only"]),
    )
    app.global_include_paths = _get_filters(g, "include_paths")
    app.global_exclude_paths = _get_filters(g, "exclude_paths")
    app.log_rotation = _deep_merge(DEFAULTS["log_rotation"], g.get("log_rotation") or {})
    app.theme = _deep_merge(DEFAULTS["theme"], g.get("theme") or {})

    for raw_inst in raw.get("instances") or []:
        inst = _load_instance(raw_inst)
        if not inst.enabled:
            continue  # 無効インスタンスは読み込むだけ保持
        inst.validate()
        if inst.discord_webhook_url == "":
            inst.discord_webhook_url = app.discord_webhook_url
        app.instances[inst.name] = inst
    return app
