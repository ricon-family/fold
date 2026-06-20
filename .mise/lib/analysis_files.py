#!/usr/bin/env python3
from __future__ import annotations

import csv
import fnmatch
import hashlib
import math
import os
import re
import shlex
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable

DEFAULT_EXCLUDES = [
    ".git/**",
    "**/.git/**",
    "node_modules/**",
    "**/node_modules/**",
    ".venv/**",
    "**/.venv/**",
    "__pycache__/**",
    "**/__pycache__/**",
    "dist/**",
    "**/dist/**",
    "build/**",
    "**/build/**",
    "target/**",
    "**/target/**",
    ".env",
    ".env.*",
    "**/.env",
    "**/.env.*",
    "secrets/**",
    "**/secrets/**",
    "*.gpg",
    "*.key",
    "*.pem",
    "id_rsa*",
    ".mise.local.toml",
]

DEFAULT_PRUNE_DIRS = {".git", "node_modules", ".venv", "__pycache__", "dist", "build", "target"}


@dataclass(frozen=True)
class Root:
    label: str
    path: Path


@dataclass(frozen=True)
class ManifestRow:
    root_label: str
    root_path: Path
    rel_path: str
    bytes: int
    rough_tokens: int
    sha256: str

    @property
    def abs_path(self) -> Path:
        return self.root_path / self.rel_path


def parse_shell_words(value: str) -> list[str]:
    if not value:
        return []
    return [item for item in shlex.split(value) if item]


def resolve_path(value: str) -> Path:
    path = Path(value).expanduser()
    if not path.is_absolute():
        path = Path.cwd() / path
    return path.resolve()


def split_root_line(line: str) -> Root | None:
    stripped = line.strip()
    if not stripped or stripped.startswith("#"):
        return None
    if "\t" in stripped:
        label, path = stripped.split("\t", 1)
        return Root(label.strip(), resolve_path(path.strip()))
    path = resolve_path(stripped)
    return Root(path.name, path)


def load_roots(root_values: Iterable[str], roots_file: str) -> list[Root]:
    roots: list[Root] = []
    for value in root_values:
        path = resolve_path(value)
        roots.append(Root(path.name, path))
    if roots_file:
        for line in resolve_path(roots_file).read_text().splitlines():
            root = split_root_line(line)
            if root is not None:
                roots.append(root)
    seen: set[Path] = set()
    unique: list[Root] = []
    for root in roots:
        if root.path in seen:
            continue
        seen.add(root.path)
        unique.append(root)
    return unique


def rel_matches(rel: str, patterns: list[str]) -> bool:
    if not patterns:
        return True
    return any(fnmatch.fnmatch(rel, pattern) for pattern in patterns)


def is_excluded(rel: str, patterns: list[str]) -> bool:
    return any(fnmatch.fnmatch(rel, pattern) for pattern in patterns)


def is_text(data: bytes) -> bool:
    if b"\0" in data:
        return False
    try:
        data.decode("utf-8")
    except UnicodeDecodeError:
        return False
    return True


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def iter_candidate_files(root: Path) -> Iterable[Path]:
    for current, dirs, files in os.walk(root):
        dirs[:] = [directory for directory in dirs if directory not in DEFAULT_PRUNE_DIRS]
        for filename in files:
            yield Path(current) / filename


def read_manifest(path: Path) -> list[ManifestRow]:
    rows: list[ManifestRow] = []
    with path.open(newline="") as f:
        reader = csv.DictReader(f, delimiter="\t")
        for row in reader:
            rows.append(
                ManifestRow(
                    root_label=row["root_label"],
                    root_path=Path(row["root_path"]),
                    rel_path=row["rel_path"],
                    bytes=int(row["bytes"]),
                    rough_tokens=int(row["rough_tokens"]),
                    sha256=row["sha256"],
                )
            )
    return rows


def write_manifest() -> int:
    workbench = resolve_path(os.environ.get("usage_workbench") or ".")
    roots_file = os.environ.get("usage_roots_file", "")
    roots = load_roots(parse_shell_words(os.environ.get("usage_root", "")), roots_file)
    includes = parse_shell_words(os.environ.get("usage_include", ""))
    excludes = DEFAULT_EXCLUDES + parse_shell_words(os.environ.get("usage_exclude", ""))
    output = resolve_path(os.environ.get("usage_output") or str(workbench / "artifacts/files/manifest.tsv"))
    skipped_output = output.with_name(output.stem + ".skipped.tsv")

    if not roots:
        print("ERROR: provide --root or --roots-file", file=sys.stderr)
        return 1

    output.parent.mkdir(parents=True, exist_ok=True)
    rows: list[ManifestRow] = []
    skipped: list[tuple[str, str, str]] = []

    for root in roots:
        if not root.path.exists():
            skipped.append((root.label, str(root.path), "root-missing"))
            continue
        for file_path in iter_candidate_files(root.path):
            rel = file_path.relative_to(root.path).as_posix()
            if not rel_matches(rel, includes):
                continue
            if is_excluded(rel, excludes):
                skipped.append((root.label, rel, "excluded"))
                continue
            data = file_path.read_bytes()
            if not is_text(data):
                skipped.append((root.label, rel, "binary-or-non-utf8"))
                continue
            rows.append(
                ManifestRow(
                    root_label=root.label,
                    root_path=root.path,
                    rel_path=rel,
                    bytes=len(data),
                    rough_tokens=math.ceil(len(data) / 4),
                    sha256=sha256(data),
                )
            )

    with output.open("w", newline="") as f:
        writer = csv.writer(f, delimiter="\t")
        writer.writerow(["root_label", "root_path", "rel_path", "bytes", "rough_tokens", "sha256"])
        for row in sorted(rows, key=lambda item: (item.root_label, item.rel_path)):
            writer.writerow([row.root_label, row.root_path, row.rel_path, row.bytes, row.rough_tokens, row.sha256])

    with skipped_output.open("w", newline="") as f:
        writer = csv.writer(f, delimiter="\t")
        writer.writerow(["root_label", "path", "reason"])
        for item in skipped:
            writer.writerow(item)

    print(output)
    print(skipped_output)
    return 0


def write_estimate() -> int:
    workbench = resolve_path(os.environ.get("usage_workbench") or ".")
    manifest = resolve_path(os.environ.get("usage_manifest") or str(workbench / "artifacts/files/manifest.tsv"))
    output = resolve_path(os.environ.get("usage_output") or str(workbench / "artifacts/files/estimate.md"))
    rows = read_manifest(manifest)
    output.parent.mkdir(parents=True, exist_ok=True)

    by_root: dict[str, tuple[int, int, int]] = {}
    for row in rows:
        files, byte_count, token_count = by_root.get(row.root_label, (0, 0, 0))
        by_root[row.root_label] = (files + 1, byte_count + row.bytes, token_count + row.rough_tokens)

    with output.open("w") as f:
        f.write("# Analysis file corpus estimate\n\n")
        f.write(f"- Files: {len(rows)}\n")
        f.write(f"- Bytes: {sum(row.bytes for row in rows):,}\n")
        f.write(f"- Rough tokens: {sum(row.rough_tokens for row in rows):,}\n")
        f.write("- Token estimate: bytes / 4, rounded up.\n\n")
        f.write("| root | files | bytes | rough tokens |\n")
        f.write("|---|---:|---:|---:|\n")
        for label, (files, byte_count, token_count) in sorted(by_root.items()):
            f.write(f"| `{label}` | {files} | {byte_count:,} | {token_count:,} |\n")
    print(output)
    return 0


def write_pack() -> int:
    workbench = resolve_path(os.environ.get("usage_workbench") or ".")
    manifest = resolve_path(os.environ.get("usage_manifest") or str(workbench / "artifacts/files/manifest.tsv"))
    output = resolve_path(os.environ.get("usage_output") or str(workbench / "artifacts/files/corpus.txt"))
    rows = read_manifest(manifest)
    output.parent.mkdir(parents=True, exist_ok=True)

    with output.open("w") as f:
        f.write("# Analysis file corpus\n")
        f.write("# Generated from manifest. Excludes are recorded in the sibling .skipped.tsv when available.\n\n")
        for row in rows:
            data = row.abs_path.read_text(errors="replace")
            f.write(f"===== FILE {row.root_label}/{row.rel_path} =====\n")
            f.write(f"root: {row.root_label}\n")
            f.write(f"path: {row.rel_path}\n")
            f.write(f"bytes: {row.bytes}\n")
            f.write(f"rough_tokens: {row.rough_tokens}\n")
            f.write(f"sha256: {row.sha256}\n\n")
            f.write(data)
            if data and not data.endswith("\n"):
                f.write("\n")
            f.write(f"===== END FILE {row.root_label}/{row.rel_path} =====\n\n")
    print(output)
    return 0


def grep_context() -> int:
    workbench = resolve_path(os.environ.get("usage_workbench") or ".")
    manifest = resolve_path(os.environ.get("usage_manifest") or str(workbench / "artifacts/files/manifest.tsv"))
    pattern = os.environ.get("usage_pattern", "")
    allow_excerpts = os.environ.get("usage_allow_excerpts", "false") == "true"
    context = int(os.environ.get("usage_context") or "2")
    output = resolve_path(os.environ.get("usage_output") or str(workbench / "artifacts/text/grep-context.md"))

    if not pattern:
        print("ERROR: --pattern is required", file=sys.stderr)
        return 1
    if not allow_excerpts:
        print("ERROR: refusing to emit text excerpts without --allow-excerpts", file=sys.stderr)
        return 1

    regex = re.compile(pattern)
    rows = read_manifest(manifest)
    output.parent.mkdir(parents=True, exist_ok=True)
    hit_count = 0

    with output.open("w") as f:
        f.write("# Analysis grep context\n\n")
        f.write(f"Pattern: `{pattern}`\n\n")
        for row in rows:
            lines = row.abs_path.read_text(errors="replace").splitlines()
            matching = [idx for idx, line in enumerate(lines, start=1) if regex.search(line)]
            if not matching:
                continue
            f.write(f"## `{row.root_label}/{row.rel_path}`\n\n")
            for line_no in matching:
                hit_count += 1
                start = max(1, line_no - context)
                end = min(len(lines), line_no + context)
                f.write(f"### line {line_no}\n\n```text\n")
                for idx in range(start, end + 1):
                    marker = ">" if idx == line_no else " "
                    f.write(f"{marker} {idx}: {lines[idx - 1]}\n")
                f.write("```\n\n")
    print(output)
    print(f"hits={hit_count}")
    return 0 if hit_count else 1
