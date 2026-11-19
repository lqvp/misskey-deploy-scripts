import textwrap

import pytest

from misskey_deploy.config import ConfigError, load_config
from misskey_deploy.filters import apply_filters

EXAMPLE_YAML = textwrap.dedent("""
    global_settings:
      discord_webhook_url: "https://discord.example/webhook"
      deploy_filters:
        include_paths:
          - "packages/backend/src/"
          - "packages/frontend/src/"
        exclude_paths:
          - "*.md"
          - "docs/"
      log_rotation:
        enabled: true
        max_size_mb: 5
        max_files: 3
    instances:
      - name: "live"
        enabled: true
        repo_dir: "/srv/misskey/live"
        repo_url: "https://github.com/misskey-dev/misskey.git"
        branch: "master"
        health_check:
          enabled: true
          url: "https://live.example.com/.well-known/nodeinfo"
          retries: 2
      - name: "dev"
        enabled: true
        repo_dir: "/srv/misskey/dev"
        repo_url: "https://github.com/misskey-dev/misskey.git"
        branch: "develop"
      - name: "disabled_inst"
        enabled: false
        repo_dir: ""
        repo_url: ""
        branch: ""
""")


@pytest.fixture
def config_file(tmp_path):
    path = tmp_path / "deploy_config.yaml"
    path.write_text(EXAMPLE_YAML, encoding="utf-8")
    return path


def test_load_config(config_file):
    app = load_config(config_file)
    assert "live" in app.instances
    assert "dev" in app.instances
    assert "disabled_inst" not in app.instances  # 無効インスタンスは除外
    live = app.instances["live"]
    assert live.branch == "master"
    assert live.health_check.retries == 2
    assert app.discord_webhook_url == "https://discord.example/webhook"


def test_missing_required_fields(tmp_path):
    bad = tmp_path / "bad.yaml"
    bad.write_text("instances:\n  - name: x\n    repo_dir: /a\n", encoding="utf-8")
    with pytest.raises(ConfigError, match="必須設定"):
        load_config(bad)


def test_missing_file(tmp_path):
    with pytest.raises(ConfigError, match="見つかりません"):
        load_config(tmp_path / "nonexistent.yaml")


def test_env_override(config_file):
    env = {
        "CONFIG_OVERRIDE_INSTANCES_INDEX_1_BRANCH": "feature/x",
        "CONFIG_OVERRIDE_GLOBAL_SETTINGS_LOG_ROTATION_MAX_SIZE_MB": "20",
    }
    app = load_config(config_file, env=env)
    assert app.instances["dev"].branch == "feature/x"
    assert app.log_rotation["max_size_mb"] == 20


def test_apply_filters_prefix_and_glob():
    changed = [
        "packages/backend/src/foo.ts",
        "README.md",
        "docs/guide.md",
        "packages/backend/test/foo.test.ts",
    ]
    result = apply_filters(
        changed,
        include_paths=["packages/backend/src/", "packages/backend/test/"],
        exclude_paths=["*.md", "docs/"],
    )
    assert "packages/backend/src/foo.ts" in result
    assert "README.md" not in result
    assert "docs/guide.md" not in result
    assert "packages/backend/test/foo.test.ts" in result


def test_apply_filters_empty_include_all():
    result = apply_filters(["a.txt", "b.log"], include_paths=[], exclude_paths=["*.log"])
    assert result == ["a.txt"]


def test_deploy_filter_singular_compat(tmp_path):
    """旧file_filter.shの deploy_filter (単数形) キー互換。"""
    path = tmp_path / "c.yaml"
    path.write_text(
        "instances:\n  - name: x\n    repo_dir: /a\n    repo_url: u\n    branch: b\n"
        "    deploy_filter:\n      include_paths: ['src/']\n",
        encoding="utf-8",
    )
    app = load_config(path)
    assert app.instances["x"].include_paths == ["src/"]
