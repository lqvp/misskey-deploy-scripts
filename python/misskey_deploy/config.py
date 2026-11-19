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


def _to_bool(value: Any) -> bool:
    if isinstance(value, bool):
        return value
    if isinstance(value, str):
        return value.strip().lower() in ("true", "yes", "on", "1")
    return bool(value)


def _to_int(value: Any, context: str) -> int:
    try:
        return int(value)
    except (TypeError, ValueError) as e:
        raise ConfigError(f"{context} は整数である必要があります (値: {value!r})") from e


def _deep_merge(base: dict, override: dict) -> dict:
    """override の値で base を再帰的に上書きする。"""
    merged = copy.deepcopy(base)
    for key, value in override.items():
        if isinstance(value, dict) and isinstance(merged.get(key), dict):
            merged[key] = _deep_merge(merged[key], value)
        else:
            merged[key] = value
    return merged


def _parse_env_value(raw: str, current: Any) -> Any:
    """環境変数の文字列値を、既存値の型に合わせて変換する。

    yaml.safe_load を使わない理由: 空文字が None、"no" が False、
    "12.10" が float になる等の暗黙変換が発生するため。
    """
    if isinstance(current, bool):
        return _to_bool(raw)
    if isinstance(current, int):
        return _to_int(raw, "環境変数オーバーライド値")
    if isinstance(current, float):
        try:
            return float(raw)
        except ValueError as e:
            raise ConfigError(f"環境変数オーバーライド値は数値である必要があります (値: {raw!r})") from e
    # str / None / 未知のキーはそのまま文字列として扱う
    return raw


def _set_override(node: Any, tokens: list, raw_value: str) -> None:
    """トークン列を既存キーに最長一致で辿り、葉に値をセットする。"""
    if not tokens:
        return
    if isinstance(node, list) and isinstance(tokens[0], int):
        index = tokens[0]
        if index >= len(node):
            raise ConfigError(f"配列インデックスが範囲外です: {index}")
        if len(tokens) == 1:
            raise ConfigError("配列要素そのものの上書きはサポートされていません (キーを指定してください)")
        _set_override(node[index], tokens[1:], raw_value)
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
                node[key] = _parse_env_value(raw_value, node[key])
            else:
                _set_override(node[key], tokens[n:], raw_value)
            return
    # 既存キーに一致しない場合は新規キーとして作成する
    # (YAMLに未定義のセクションを環境変数で有効化するユースケースのため)
    key = "_".join(tokens)
    if isinstance(node, dict):
        node[key] = _parse_env_value(raw_value, None)
        return
    raise ConfigError(
        f"環境変数オーバーライドのパスが設定内のキーに一致しません: {'_'.join(map(str, tokens))}"
    )


def _seed_known_sections(config: dict) -> None:
    """環境変数オーバーライドが既知セクション内のキーを指せるよう、
    YAMLに未定義の既知セクションを空 dict として用意する。"""
    g = config.setdefault("global_settings", {})
    if isinstance(g, dict):
        for key in ("misskey_notification", "log_rotation", "theme", "deploy_filters"):
            g.setdefault(key, {})
    for inst in config.get("instances") or []:
        if isinstance(inst, dict):
            for key in ("health_check", "misskey_notification", "deploy_filters", "deploy_filter"):
                inst.setdefault(key, {})


def _apply_env_overrides(config: dict, env: dict[str, str] | None = None) -> dict:
    """CONFIG_OVERRIDE_ 接頭辞の環境変数で設定を上書きする。

    例: CONFIG_OVERRIDE_GLOBAL_SETTINGS_LOG_ROTATION_MAX_SIZE_MB=20 は
    global_settings.log_rotation.max_size_mb を上書きする。
    インスタンス配列は _INDEX_<n>_ で指定する。
    """
    env = env if env is not None else os.environ
    _seed_known_sections(config)
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
        _set_override(config, parsed, value)
    return config


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


def _parse_misskey_notification(raw: dict) -> MisskeyNotificationConfig:
    mn = {**DEFAULTS["misskey_notification"], **(raw or {})}
    return MisskeyNotificationConfig(
        enabled=_to_bool(mn["enabled"]),
        host=str(mn["host"]),
        token=str(mn["token"]),
        visibility=str(mn["visibility"]),
        local_only=_to_bool(mn["local_only"]),
    )


def _parse_health_check(raw: dict) -> HealthCheckConfig:
    hc = {**DEFAULTS["health_check"], **(raw or {})}
    ctx = "health_check"
    return HealthCheckConfig(
        enabled=_to_bool(hc["enabled"]),
        url=str(hc["url"]),
        timeout_seconds=_to_int(hc["timeout_seconds"], f"{ctx}.timeout_seconds"),
        retries=_to_int(hc["retries"], f"{ctx}.retries"),
        retry_delay_seconds=_to_int(hc["retry_delay_seconds"], f"{ctx}.retry_delay_seconds"),
        expected_status_code=_to_int(hc["expected_status_code"], f"{ctx}.expected_status_code"),
        expected_response_contains=str(hc["expected_response_contains"]),
    )


def _load_instance(raw: dict, global_misskey: MisskeyNotificationConfig,
                   global_discord_webhook: str) -> InstanceConfig:
    """未設定項目はグローバル設定からのフォールバックを解決済みの状態で返す。"""
    inst = InstanceConfig(
        name=str(raw["name"]),
        enabled=_to_bool(raw.get("enabled", True)),
        repo_dir=str(raw.get("repo_dir", "")),
        repo_url=str(raw.get("repo_url", "")),
        branch=str(raw.get("branch", "")),
        discord_webhook_url=str(raw.get("discord_webhook_url", "")) or global_discord_webhook,
        misskey_notification=_parse_misskey_notification(raw.get("misskey_notification")),
        health_check=_parse_health_check(raw.get("health_check")),
        include_paths=_get_filters(raw, "include_paths"),
        exclude_paths=_get_filters(raw, "exclude_paths"),
    )
    mn = inst.misskey_notification
    if not mn.host:
        mn.host = global_misskey.host
    if not mn.token:
        mn.token = global_misskey.token
    return inst


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
    if not isinstance(g, dict):
        raise ConfigError("global_settings はマップである必要があります")
    app.discord_webhook_url = str(g.get("discord_webhook_url", ""))
    app.misskey_notification = _parse_misskey_notification(g.get("misskey_notification"))
    app.global_include_paths = _get_filters(g, "include_paths")
    app.global_exclude_paths = _get_filters(g, "exclude_paths")
    app.log_rotation = _deep_merge(DEFAULTS["log_rotation"], g.get("log_rotation") or {})
    app.theme = _deep_merge(DEFAULTS["theme"], g.get("theme") or {})

    instances_raw = raw.get("instances") or []
    if not isinstance(instances_raw, list):
        raise ConfigError("instances はリストである必要があります")
    for raw_inst in instances_raw:
        if not isinstance(raw_inst, dict) or "name" not in raw_inst:
            raise ConfigError(f"instances の各要素は name を持つマップである必要があります: {raw_inst!r}")
        inst = _load_instance(raw_inst, app.misskey_notification, app.discord_webhook_url)
        if not inst.enabled:
            continue  # 無効インスタンスは読み込むだけ保持
        if inst.name in app.instances:
            raise ConfigError(f"インスタンス名が重複しています: {inst.name}")
        inst.validate()
        app.instances[inst.name] = inst
    return app
