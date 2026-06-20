#!/usr/bin/env python3
from __future__ import annotations

import csv
import json
import math
import os
import shlex
import subprocess
import sys
from collections import Counter
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

FAILURE_MARKERS = ("Command exited with code ", "Command timed out", "ERROR task failed", "timed out after")


def resolve_path(value: str) -> Path:
    path = Path(value).expanduser()
    if not path.is_absolute():
        path = Path.cwd() / path
    return path.resolve()


def load_json(path: Path, default: Any) -> Any:
    if not path.exists():
        return default
    with path.open() as f:
        return json.load(f)


def dump_json(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")


def parse_ts(value: str | None) -> datetime | None:
    if not value:
        return None
    try:
        return datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None


def seconds_between(first: datetime | None, second: datetime | None) -> float:
    if first is None or second is None:
        return 0.0
    return max(0.0, (second - first).total_seconds())


def percentile(values: list[float], pct: float) -> float:
    if not values:
        return 0.0
    ordered = sorted(values)
    if len(ordered) == 1:
        return ordered[0]
    idx = (len(ordered) - 1) * pct
    lo = math.floor(idx)
    hi = math.ceil(idx)
    if lo == hi:
        return ordered[lo]
    return ordered[lo] * (hi - idx) + ordered[hi] * (idx - lo)


def money(value: float) -> str:
    return f"${value:,.2f}"


def run_json(args: list[str]) -> Any:
    completed = subprocess.run(args, check=True, text=True, capture_output=True)
    return json.loads(completed.stdout)


def sessions_bin() -> str:
    return os.environ.get("SESSIONS") or "sessions"


def metadata() -> int:
    workbench = resolve_path(os.environ.get("usage_workbench") or ".")
    out_dir = workbench / "artifacts/sessions"
    limit = os.environ.get("usage_limit") or "80"
    include_all = os.environ.get("usage_all", "false") == "true"
    project = os.environ.get("usage_project", "")
    out_dir.mkdir(parents=True, exist_ok=True)

    list_args = [sessions_bin(), "list", "--json", "--limit", limit]
    usage_args = [sessions_bin(), "usage", "--json", "--limit", limit]
    if include_all:
        list_args.append("--all")
        usage_args.append("--all")
    if project:
        list_args.extend(["--project", project])
        usage_args.extend(["--project", project])

    dump_json(out_dir / "list.json", run_json(list_args))
    dump_json(out_dir / "usage.json", run_json(usage_args))
    dump_json(
        out_dir / "provenance.json",
        {
            "captured_at": datetime.now(timezone.utc).isoformat(),
            "privacy": "metadata-only: sessions list/usage JSON, no transcript text",
            "commands": {"list": list_args, "usage": usage_args},
        },
    )
    print(out_dir / "list.json")
    print(out_dir / "usage.json")
    print(out_dir / "provenance.json")
    return 0


@dataclass
class RankRow:
    session_id: str
    project: str = ""
    name: str = ""
    model: str = ""
    first_timestamp: str = ""
    last_timestamp: str = ""
    entries: int = 0
    user_messages: int = 0
    assistant_messages: int = 0
    filepath: str = ""
    calls: int = 0
    input_tokens: int = 0
    output_tokens: int = 0
    cache_read_tokens: int = 0
    total_tokens: int = 0
    cost_total: float = 0.0

    @property
    def wall_hours(self) -> float:
        return seconds_between(parse_ts(self.first_timestamp), parse_ts(self.last_timestamp)) / 3600.0

    def score(self) -> int:
        score = 0
        if self.cost_total >= 25:
            score += 6
        elif self.cost_total >= 10:
            score += 4
        elif self.cost_total >= 2:
            score += 2
        if self.calls >= 300:
            score += 5
        elif self.calls >= 100:
            score += 3
        if self.wall_hours >= 24:
            score += 5
        elif self.wall_hours >= 6:
            score += 3
        elif self.wall_hours >= 2:
            score += 1
        if self.assistant_messages >= 300:
            score += 4
        elif self.assistant_messages >= 100:
            score += 2
        if self.entries >= 1000:
            score += 3
        elif self.entries >= 500:
            score += 1
        if self.output_tokens >= 100_000:
            score += 3
        elif self.output_tokens >= 30_000:
            score += 1
        return score


def rank_rows(metadata_dir: Path) -> list[RankRow]:
    by_id: dict[str, RankRow] = {}
    for entry in load_json(metadata_dir / "list.json", []):
        sid = str(entry.get("session_id") or "")
        if not sid:
            continue
        by_id[sid] = RankRow(
            session_id=sid,
            project=str(entry.get("project") or ""),
            name=str(entry.get("name") or ""),
            model=str(entry.get("model") or ""),
            first_timestamp=str(entry.get("first_timestamp") or ""),
            last_timestamp=str(entry.get("last_timestamp") or ""),
            entries=int(entry.get("total_entries") or 0),
            user_messages=int(entry.get("user_messages") or 0),
            assistant_messages=int(entry.get("assistant_messages") or 0),
            filepath=str(entry.get("filepath") or ""),
        )
    for entry in load_json(metadata_dir / "usage.json", {}).get("sessions", []):
        sid = str(entry.get("session_id") or "")
        if not sid:
            continue
        row = by_id.setdefault(sid, RankRow(session_id=sid))
        row.project = row.project or str(entry.get("project") or "")
        row.name = row.name or str(entry.get("name") or "")
        row.first_timestamp = row.first_timestamp or str(entry.get("first_timestamp") or "")
        row.last_timestamp = row.last_timestamp or str(entry.get("last_timestamp") or "")
        totals = entry.get("totals") or {}
        cost = totals.get("cost") or {}
        row.calls = int(totals.get("calls") or 0)
        row.input_tokens = int(totals.get("input") or 0)
        row.output_tokens = int(totals.get("output") or 0)
        row.cache_read_tokens = int(totals.get("cacheRead") or 0)
        row.total_tokens = int(totals.get("totalTokens") or 0)
        row.cost_total = float(cost.get("total") or 0.0)
    return list(by_id.values())


def rank() -> int:
    workbench = resolve_path(os.environ.get("usage_workbench") or ".")
    metadata_dir = resolve_path(os.environ.get("usage_metadata_dir") or str(workbench / "artifacts/sessions"))
    inspect_limit = int(os.environ.get("usage_inspect_limit") or "12")
    rows = sorted(rank_rows(metadata_dir), key=lambda row: (row.score(), row.cost_total, row.calls), reverse=True)
    tsv = metadata_dir / "rank.tsv"
    md = workbench / "artifacts/sessions-rank.md"
    candidates = metadata_dir / "inspect-candidates.txt"

    with tsv.open("w", newline="") as f:
        writer = csv.writer(f, delimiter="\t")
        writer.writerow(["session_id", "project", "name", "model", "cost_total", "calls", "wall_hours", "entries", "user_messages", "assistant_messages", "score", "filepath"])
        for row in rows:
            writer.writerow([row.session_id, row.project, row.name, row.model, f"{row.cost_total:.6f}", row.calls, f"{row.wall_hours:.2f}", row.entries, row.user_messages, row.assistant_messages, row.score(), row.filepath])
    with candidates.open("w") as f:
        for row in rows[:inspect_limit]:
            f.write(row.session_id + "\n")
    with md.open("w") as f:
        f.write("# Session rank\n\n")
        f.write("Privacy boundary: list/usage metadata only; no transcript text.\n\n")
        f.write("| rank | session | project | cost | calls | wall | entries | score |\n")
        f.write("|---:|---|---|---:|---:|---:|---:|---:|\n")
        for idx, row in enumerate(rows[:20], start=1):
            f.write(f"| {idx} | `{row.session_id[:8]}` | `{row.project or '—'}` | {money(row.cost_total)} | {row.calls:,} | {row.wall_hours:.1f}h | {row.entries:,} | {row.score()} |\n")
    print(tsv)
    print(candidates)
    print(md)
    return 0


def inspect() -> int:
    workbench = resolve_path(os.environ.get("usage_workbench") or ".")
    metadata_dir = resolve_path(os.environ.get("usage_metadata_dir") or str(workbench / "artifacts/sessions"))
    ids_file = resolve_path(os.environ.get("usage_ids_file") or str(metadata_dir / "inspect-candidates.txt"))
    inspect_dir = metadata_dir / "inspect"
    inspect_dir.mkdir(parents=True, exist_ok=True)
    failed = 0
    for sid in [line.strip() for line in ids_file.read_text().splitlines() if line.strip()]:
        try:
            data = run_json([sessions_bin(), "inspect", "--json", sid])
        except subprocess.CalledProcessError as exc:
            failed += 1
            print(f"WARN: inspect failed for {sid}: {exc}", file=sys.stderr)
            continue
        dump_json(inspect_dir / f"{sid}.json", data)
        print(inspect_dir / f"{sid}.json")
    return 1 if failed else 0


def command_category(command: str) -> str:
    lower = command.lower().strip()
    if "test" in lower or "bats" in lower:
        return "test"
    if "lint" in lower or "shellcheck" in lower or "diff --check" in lower or "bash -n" in lower:
        return "lint/validation"
    if lower.startswith("git ") or lower.startswith("gh ") or " gh " in lower or " git " in lower:
        return "git/gh"
    if "sessions" in lower or "sphincters" in lower or "shimmer" in lower:
        return "sessions/drone"
    if lower.startswith(("rg ", "grep ", "find ", "ls ", "jq ")) or " grep " in lower:
        return "search/list"
    if lower.startswith(("python", "node", "bun")) or "<<'" in lower:
        return "script"
    if lower.startswith(("cp ", "mv ", "rm ", "mkdir ", "chmod ", "touch ")):
        return "file-op"
    return "other"


def structure() -> int:
    workbench = resolve_path(os.environ.get("usage_workbench") or ".")
    metadata_dir = resolve_path(os.environ.get("usage_metadata_dir") or str(workbench / "artifacts/sessions"))
    rows = rank_rows(metadata_dir)
    out_tsv = metadata_dir / "structure.tsv"
    out_md = workbench / "artifacts/sessions-structure.md"
    records = []

    for row in rows:
        filepath = Path(row.filepath)
        event_times: list[datetime] = []
        model_times: list[datetime] = []
        tool_names: Counter[str] = Counter()
        bash_categories: Counter[str] = Counter()
        tool_results = 0
        failure_markers = 0
        path_count = 0
        unique_path_keys: set[tuple[str, str]] = set()
        if filepath.exists():
            with filepath.open() as f:
                for line in f:
                    try:
                        obj = json.loads(line)
                    except json.JSONDecodeError:
                        continue
                    ts = parse_ts(obj.get("timestamp"))
                    if ts is not None:
                        event_times.append(ts)
                    if obj.get("type") != "message":
                        continue
                    message = obj.get("message") or {}
                    role = message.get("role")
                    if role == "assistant" and message.get("usage") and ts is not None:
                        model_times.append(ts)
                    if role == "toolResult":
                        tool_results += 1
                        name = str(message.get("toolName") or "<unknown>")
                        tool_names[name] += 1
                        for block in message.get("content") or []:
                            if isinstance(block, dict):
                                text = block.get("text")
                                if isinstance(text, str) and any(marker in text for marker in FAILURE_MARKERS):
                                    failure_markers += 1
                                    break
                    if role == "assistant":
                        for block in message.get("content") or []:
                            if not isinstance(block, dict) or block.get("type") != "toolCall":
                                continue
                            name = str(block.get("name") or "<unknown>")
                            args = block.get("arguments") or {}
                            if name == "bash" and isinstance(args, dict):
                                bash_categories[command_category(str(args.get("command") or ""))] += 1
                            if name in {"read", "edit", "write"} and isinstance(args, dict):
                                path = str(args.get("path") or "")
                                if path:
                                    path_count += 1
                                    p = Path(path)
                                    unique_path_keys.add((p.suffix.lower() or "<none>", p.parts[0] if p.parts else "<root>"))
        gaps = [seconds_between(a, b) for a, b in zip(sorted(event_times), sorted(event_times)[1:])]
        active30 = sum(min(gap, 30 * 60) for gap in gaps) / 3600.0 if gaps else 0.0
        idle30 = sum(max(0.0, gap - 30 * 60) for gap in gaps) / 3600.0 if gaps else 0.0
        idle_ratio = idle30 / row.wall_hours if row.wall_hours > 0 else 0.0
        labels = []
        if row.wall_hours >= 6 and idle_ratio >= 0.5:
            labels.append("long-open/idle-heavy")
        if row.calls >= 100 and active30 > 0 and row.calls / active30 >= 80:
            labels.append("dense-model-loop")
        if tool_results >= 100:
            labels.append("tool-heavy")
        if tool_names.get("bash", 0) >= 100:
            labels.append("bash-heavy")
        if tool_names.get("read", 0) >= 60:
            labels.append("read-heavy")
        if failure_markers >= 10:
            labels.append("failure/retry-heavy")
        if bash_categories.get("git/gh", 0) >= 30:
            labels.append("git/gh-heavy")
        if bash_categories.get("test", 0) + bash_categories.get("lint/validation", 0) >= 30:
            labels.append("validation-heavy")
        records.append({
            "row": row,
            "active30": active30,
            "idle_ratio": idle_ratio,
            "tool_results": tool_results,
            "failure_markers": failure_markers,
            "path_count": path_count,
            "path_shape_count": len(unique_path_keys),
            "labels": labels or ["metadata-baseline"],
            "tool_names": tool_names,
            "bash_categories": bash_categories,
        })

    def structural_score(record: dict[str, Any]) -> tuple[int, float]:
        row = record["row"]
        labels = set(record["labels"])
        score = row.score()
        score += 3 if "failure/retry-heavy" in labels else 0
        score += 2 if "dense-model-loop" in labels else 0
        score += 2 if "long-open/idle-heavy" in labels else 0
        return score, row.cost_total

    records.sort(key=structural_score, reverse=True)
    with out_tsv.open("w", newline="") as f:
        writer = csv.writer(f, delimiter="\t")
        writer.writerow(["session_id", "project", "cost_total", "calls", "wall_hours", "active30_hours", "idle_ratio", "tool_results", "failure_markers", "path_count", "path_shape_count", "labels", "tool_names", "bash_categories"])
        for record in records:
            row = record["row"]
            writer.writerow([row.session_id, row.project, f"{row.cost_total:.6f}", row.calls, f"{row.wall_hours:.2f}", f"{record['active30']:.2f}", f"{record['idle_ratio']:.3f}", record["tool_results"], record["failure_markers"], record["path_count"], record["path_shape_count"], ",".join(record["labels"]), compact_counter(record["tool_names"]), compact_counter(record["bash_categories"])])
    with out_md.open("w") as f:
        f.write("# Session structural scan\n\n")
        f.write("Privacy boundary: structural JSONL fields only; no message text, command strings, tool output excerpts, or file paths are emitted.\n\n")
        f.write("| rank | session | project | cost | calls | wall | active30 | idle ratio | failures | labels |\n")
        f.write("|---:|---|---|---:|---:|---:|---:|---:|---:|---|\n")
        for idx, record in enumerate(records[:20], start=1):
            row = record["row"]
            f.write(f"| {idx} | `{row.session_id[:8]}` | `{row.project or '—'}` | {money(row.cost_total)} | {row.calls:,} | {row.wall_hours:.1f}h | {record['active30']:.1f}h | {record['idle_ratio']:.2f} | {record['failure_markers']} | {', '.join(record['labels'])} |\n")
    print(out_tsv)
    print(out_md)
    return 0


def compact_counter(counter: Counter[str], limit: int = 5) -> str:
    return ",".join(f"{key}:{value}" for key, value in counter.most_common(limit))
