#!/usr/bin/env python3
"""Detect trusted, non-quoted fold agent mentions in issue comments."""

from __future__ import annotations

import json
import os
import re
import sys
import textwrap
import uuid
from pathlib import Path

MENTION_RE = re.compile(r"(?<![\w/.-])@([A-Za-z0-9][A-Za-z0-9-]*)\b")
FENCE_RE = re.compile(r"^\s*(```|~~~)")


def csv_env(name: str, default: str) -> list[str]:
    return [item.strip().lower() for item in os.environ.get(name, default).split(",") if item.strip()]


def strip_non_waking_text(body: str) -> str:
    lines: list[str] = []
    in_fence = False

    for line in body.splitlines():
        if FENCE_RE.match(line):
            in_fence = not in_fence
            continue
        if in_fence:
            continue
        if line.lstrip().startswith(">"):
            continue
        lines.append(line)

    return "\n".join(lines)


def output(name: str, value: str) -> None:
    output_path = os.environ.get("GITHUB_OUTPUT")
    if not output_path:
        print(f"{name}={value}")
        return

    with open(output_path, "a", encoding="utf-8") as handle:
        if "\n" in value:
            delimiter = f"EOF_{uuid.uuid4().hex}"
            handle.write(f"{name}<<{delimiter}\n{value}\n{delimiter}\n")
        else:
            handle.write(f"{name}={value}\n")


def set_no_wake(reason: str, roster: list[str]) -> None:
    output("should_wake", "false")
    output("reason", reason)
    output("matched_agents", "[]")
    for agent in roster:
        output(f"agent_{agent.replace('-', '_')}", "false")
    output("message", "")


def build_message(event: dict, matched_agents: list[str], matched_mentions: list[str]) -> str:
    repo = event["repository"]["full_name"]
    issue = event["issue"]
    comment = event["comment"]
    thread_kind = "pull request" if "pull_request" in issue else "issue"
    author = comment["user"]["login"]
    association = comment.get("author_association", "UNKNOWN")
    body = comment.get("body") or ""

    return textwrap.dedent(
        f"""
        GitHub mention wake: {repo}#{issue['number']} ({thread_kind})
        Thread: {issue.get('html_url', '')}
        Comment: {comment.get('html_url', '')}
        Author: @{author} ({association})
        Mentions: {', '.join('@' + mention for mention in matched_mentions)}
        Agents: {', '.join(matched_agents)}

        Inspect the thread yourself before responding. Reply on GitHub if useful.

        Comment body:
        ---
        {body}
        ---
        """
    ).strip()


def main() -> int:
    event_path = os.environ.get("GITHUB_EVENT_PATH")
    if not event_path:
        print("GITHUB_EVENT_PATH is required", file=sys.stderr)
        return 2

    event = json.loads(Path(event_path).read_text(encoding="utf-8"))
    roster = csv_env("AGENT_ROSTER", "quick")
    aliases = csv_env("TEAM_ALIASES", "agents")
    allowed_associations = {item.upper() for item in csv_env("ALLOWED_ASSOCIATIONS", "OWNER,MEMBER,COLLABORATOR")}

    association = (event.get("comment", {}).get("author_association") or "UNKNOWN").upper()
    if association not in allowed_associations:
        set_no_wake(f"comment author association {association} is not allowed", roster)
        return 0

    body = event.get("comment", {}).get("body") or ""
    stripped_body = strip_non_waking_text(body)
    mentions = [match.group(1).lower() for match in MENTION_RE.finditer(stripped_body)]

    matched_agents: set[str] = set()
    matched_mentions: list[str] = []
    for mention in mentions:
        if mention in roster:
            matched_agents.add(mention)
            matched_mentions.append(mention)
        elif mention in aliases:
            matched_agents.update(roster)
            matched_mentions.append(mention)

    ordered_agents = [agent for agent in roster if agent in matched_agents]
    if not ordered_agents:
        set_no_wake("no agent mention found outside quotes/code", roster)
        return 0

    for agent in roster:
        output(f"agent_{agent.replace('-', '_')}", "true" if agent in matched_agents else "false")

    output("should_wake", "true")
    output("reason", "matched agent mention")
    output("matched_agents", json.dumps(ordered_agents))
    output("message", build_message(event, ordered_agents, matched_mentions))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
