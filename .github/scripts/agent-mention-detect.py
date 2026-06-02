#!/usr/bin/env python3
"""Detect trusted agent mentions in GitHub issue comments."""

from __future__ import annotations

import json
import os
import re
import sys
import uuid
from pathlib import Path
from typing import Any

MENTION_PATTERN = re.compile(
    r"(^|[^\w/.-])@(?P<mention>[A-Za-z0-9][A-Za-z0-9-]*(/[A-Za-z0-9][A-Za-z0-9-]*)?)"
)


def csv_env(name: str, default: str = "") -> list[str]:
    """Read a comma-separated environment variable as lowercase tokens."""
    raw = os.environ.get(name, default)
    return [item.strip().lower() for item in raw.split(",") if item.strip()]


def load_event(path: str) -> dict[str, Any]:
    """Load the GitHub event payload."""
    return json.loads(Path(path).read_text(encoding="utf-8"))


def output_name(agent: str) -> str:
    """Convert an agent name into a GitHub-output-safe suffix."""
    return agent.replace("-", "_")


def write_output(name: str, value: str) -> None:
    """Write a GitHub Actions output, falling back to stdout for local runs."""
    output_path = os.environ.get("GITHUB_OUTPUT", "")
    if not output_path:
        print(f"{name}={value}")
        return

    path = Path(output_path)
    if "\n" in value:
        delimiter = f"EOF_{uuid.uuid4().hex}"
        record = f"{name}<<{delimiter}\n{value}\n{delimiter}\n"
    else:
        record = f"{name}={value}\n"
    with path.open("a", encoding="utf-8") as handle:
        handle.write(record)


def set_no_wake(reason: str, roster: list[str]) -> None:
    """Emit outputs for a non-waking comment."""
    write_output("should_wake", "false")
    write_output("reason", reason)
    write_output("matched_agents", "[]")
    for agent in roster:
        write_output(f"agent_{output_name(agent)}", "false")
    write_output("message", "")


def strip_inline_code(line: str) -> str:
    """Remove balanced Markdown inline-code spans from one line."""
    stripped: list[str] = []
    index = 0
    length = len(line)

    while index < length:
        if line[index] != "`":
            stripped.append(line[index])
            index += 1
            continue

        end = index + 1
        while end < length and line[end] == "`":
            end += 1

        delimiter = line[index:end]
        close = line.find(delimiter, end)
        if close == -1:
            stripped.append(delimiter)
            index = end
        else:
            index = close + len(delimiter)

    return "".join(stripped)


def strip_non_waking_text(body: str) -> str:
    """Remove Markdown regions where mentions should not wake agents."""
    kept_lines: list[str] = []
    in_fence = False

    for line in body.split("\n"):
        stripped = line.strip()
        if stripped.startswith("```") or stripped.startswith("~~~"):
            in_fence = not in_fence
            continue
        if in_fence:
            continue
        if line.lstrip().startswith(">"):
            continue
        kept_lines.append(strip_inline_code(line))

    return "\n".join(kept_lines)


def extract_mentions(body: str) -> list[str]:
    """Return lowercase GitHub-style mentions from stripped Markdown."""
    return [match.group("mention").lower() for match in MENTION_PATTERN.finditer(body)]


def match_agents(
    mentions: list[str],
    roster: list[str],
    handle_suffix: str,
    aliases: list[str],
) -> tuple[list[str], list[str]]:
    """Map mentions to agents while preserving roster order for wake outputs."""
    agent_by_mention = {f"{agent}{handle_suffix}": agent for agent in roster}
    matched_agents: set[str] = set()
    matched_mentions: list[str] = []

    for mention in mentions:
        if mention in agent_by_mention:
            matched_agents.add(agent_by_mention[mention])
            matched_mentions.append(mention)
        elif mention in aliases:
            matched_agents.update(roster)
            matched_mentions.append(mention)

    ordered_agents = [agent for agent in roster if agent in matched_agents]
    return ordered_agents, matched_mentions


def event_value(event: dict[str, Any], *path: str, default: str = "") -> Any:
    """Safely read a nested value from the event payload."""
    current: Any = event
    for key in path:
        if not isinstance(current, dict):
            return default
        current = current.get(key)
        if current is None:
            return default
    return current


def build_message(
    event: dict[str, Any], matched_agents: list[str], matched_mentions: list[str]
) -> str:
    """Build the prompt sent to matched agents."""
    issue = event.get("issue", {}) if isinstance(event.get("issue"), dict) else {}
    comment = event.get("comment", {}) if isinstance(event.get("comment"), dict) else {}

    repo = event_value(event, "repository", "full_name")
    issue_number = issue.get("number", "")
    thread_kind = "pull request" if "pull_request" in issue else "issue"
    thread_url = issue.get("html_url", "")
    comment_url = comment.get("html_url", "")
    author = event_value(event, "comment", "user", "login")
    association = str(comment.get("author_association") or "UNKNOWN")
    body = str(comment.get("body") or "")
    mention_text = ", ".join(f"@{mention}" for mention in matched_mentions)
    agent_text = ", ".join(matched_agents)

    return f"""GitHub mention wake: {repo}#{issue_number} ({thread_kind})
Thread: {thread_url}
Comment: {comment_url}
Author: @{author} ({association})
Mentions: {mention_text}
Agents: {agent_text}

Inspect the thread yourself before responding. Reply on GitHub if useful.

Comment body:
---
{body}
---"""


def main() -> int:
    """GitHub Actions entrypoint."""
    event_path = os.environ.get("GITHUB_EVENT_PATH", "")
    if not event_path:
        print("GITHUB_EVENT_PATH is required", file=sys.stderr)
        return 2

    event = load_event(event_path)
    roster = csv_env("AGENT_ROSTER")
    aliases = csv_env("TEAM_ALIASES")
    handle_suffix = os.environ.get("AGENT_HANDLE_SUFFIX", "-ricon").strip().lower()
    allowed_associations = {
        association.upper() for association in csv_env("ALLOWED_ASSOCIATIONS", "OWNER,MEMBER")
    }

    if not roster:
        set_no_wake("agent roster is empty", [])
        return 0

    association = str(event_value(event, "comment", "author_association", default="UNKNOWN")).upper()
    if association not in allowed_associations:
        set_no_wake(f"comment author association ({association}) is not allowed", roster)
        return 0

    body = str(event_value(event, "comment", "body"))
    stripped_body = strip_non_waking_text(body)
    mentions = extract_mentions(stripped_body)
    matched_agents, matched_mentions = match_agents(mentions, roster, handle_suffix, aliases)

    if not matched_agents:
        set_no_wake("no agent mention found outside quotes/code", roster)
        return 0

    matched_set = set(matched_agents)
    for agent in roster:
        write_output(f"agent_{output_name(agent)}", "true" if agent in matched_set else "false")

    write_output("should_wake", "true")
    write_output("reason", "matched agent mention")
    write_output("matched_agents", json.dumps(matched_agents, separators=(",", ":")))
    write_output("message", build_message(event, matched_agents, matched_mentions))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
