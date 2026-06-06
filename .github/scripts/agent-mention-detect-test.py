#!/usr/bin/env python3
"""Smoke tests for the fold agent mention detector."""

from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

SCRIPT = Path(__file__).with_name("agent-mention-detect.py")
ROSTER = [
    "baby-joel",
    "brownie",
    "c0da",
    "ikma",
    "iris",
    "johnson",
    "junior",
    "k7r2",
    "quick",
    "rho",
    "x1f9",
    "zeke",
]


def event(body: str, association: str = "MEMBER") -> dict:
    return {
        "repository": {"full_name": "ricon-family/fold"},
        "issue": {"number": 72, "html_url": "https://github.com/ricon-family/fold/issues/72"},
        "comment": {
            "html_url": "https://github.com/ricon-family/fold/issues/72#issuecomment-test",
            "author_association": association,
            "user": {"login": "quick-ricon"},
            "body": body,
        },
    }


def parse_output(output: str) -> dict[str, str]:
    parsed: dict[str, str] = {}
    for line in output.splitlines():
        if "=" not in line:
            continue
        key, value = line.split("=", 1)
        if key == "message" or key.startswith("agent_") or key in {"should_wake", "reason", "matched_agents"}:
            parsed[key] = value
    return parsed


def run_detector(body: str, association: str = "MEMBER") -> dict[str, str]:
    with tempfile.TemporaryDirectory() as tmp:
        event_path = Path(tmp) / "event.json"
        event_path.write_text(json.dumps(event(body, association)), encoding="utf-8")
        env = os.environ.copy()
        env.update(
            {
                "GITHUB_EVENT_PATH": str(event_path),
                "AGENT_ROSTER": ",".join(ROSTER),
                "AGENT_GITHUB_LOGINS": json.dumps(
                    {agent: (agent if agent == "baby-joel" else f"{agent}-ricon") for agent in ROSTER}
                ),
                # Team aliases intentionally disabled for the individual-handle pilot.
                "TEAM_ALIASES": "",
                "ALLOWED_ASSOCIATIONS": "OWNER,MEMBER,COLLABORATOR",
            }
        )
        result = subprocess.run(
            [sys.executable, str(SCRIPT)],
            check=True,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env=env,
        )
        return parse_output(result.stdout)


def assert_case(name: str, body: str, expected_agents: list[str], association: str = "MEMBER") -> None:
    output = run_detector(body, association)
    expected_wake = "true" if expected_agents else "false"
    assert output.get("should_wake") == expected_wake, (name, output)

    for agent in ROSTER:
        key = f"agent_{agent.replace('-', '_')}"
        expected = "true" if agent in expected_agents else "false"
        assert output.get(key) == expected, (name, key, output)

    if expected_agents:
        assert json.loads(output["matched_agents"]) == expected_agents, (name, output)


def main() -> int:
    for agent in ROSTER:
        if agent == "baby-joel":
            assert_case(f"{agent} real handle", "@baby-joel hello", [agent])
            continue
        assert_case(f"{agent} real handle", f"@{agent}-ricon hello", [agent])

    assert_case("mapped login avoids suffix guess", "@baby-joel-ricon hello", [])
    assert_case("multiple individual handles", "@quick-ricon @c0da-ricon", ["c0da", "quick"])
    assert_case("naked quick does not match", "@quick hello", [])
    assert_case("naked agents does not match", "@agents hello", [])
    assert_case("team alias disabled", "@ricon-family/agents hello", [])
    assert_case("quoted handle ignored", "> @quick-ricon quoted", [])
    assert_case("fenced handle ignored", "```\n@quick-ricon fenced\n```", [])
    assert_case("nested path does not partial match", "@quick-ricon/foo no", [])
    assert_case("untrusted association ignored", "@quick-ricon hello", [], association="NONE")

    print("agent mention detector tests: ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
