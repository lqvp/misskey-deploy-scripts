"""デプロイフィルタ: include/exclude パスルールの適用。"""
from __future__ import annotations

from fnmatch import fnmatch


def _matches(file_path: str, pattern: str) -> bool:
    """bash の [[ "$file" == "$pattern"* ]] 相当: 前方一致または fnmatch。"""
    if file_path == pattern or file_path.startswith(pattern):
        return True
    # "*.md" のようなグロブパターンは fnmatch で扱う
    if any(c in pattern for c in "*?["):
        return fnmatch(file_path, pattern) or fnmatch(file_path, pattern + "*")
    return False


def apply_filters(
    changed_files: list[str],
    include_paths: list[str],
    exclude_paths: list[str],
) -> list[str]:
    """変更ファイルに include/exclude フィルタを適用し、デプロイ対象を返す。

    - include_paths が空なら全ファイルが対象
    - exclude_paths に前方一致/グロブ一致するファイルは除外
    """
    deploy_files: list[str] = []
    for file_path in changed_files:
        if include_paths:
            if not any(_matches(file_path, p) for p in include_paths):
                continue
        if exclude_paths and any(_matches(file_path, p) for p in exclude_paths):
            continue
        deploy_files.append(file_path)
    return deploy_files
