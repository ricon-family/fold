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
REPO_ROOT = SCRIPT.parents[2]


def load_agent_metadata() -> list[dict[str, str]]:
    result = subprocess.run(
        ["mise", "run", "-q", "agent:list", "--", "--ci", "--json"],
        cwd=REPO_ROOT,
        check=True,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    records = json.loads(result.stdout)
    assert isinstance(records, list), records

    metadata: list[dict[str, str]] = []
    for record in records:
        assert isinstance(record, dict), record
        name = record.get("name")
        github_login = record.get("github_login")
        assert isinstance(name, str) and name, record
        assert isinstance(github_login, str) and github_login, record
        metadata.append({"name": name, "github_login": github_login})

    assert metadata, "agent:list --ci --json returned no agents"
    return metadata


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


def run_detector(
    body: str,
    roster: list[str],
    github_logins: dict[str, str],
    association: str = "MEMBER",
) -> dict[str, str]:
    with tempfile.TemporaryDirectory() as tmp:
        event_path = Path(tmp) / "event.json"
        event_path.write_text(json.dumps(event(body, association)), encoding="utf-8")
        env = os.environ.copy()
        env.update(
            {
                "GITHUB_EVENT_PATH": str(event_path),
                "AGENT_ROSTER": ",".join(roster),
                "AGENT_GITHUB_LOGINS": json.dumps(github_logins),
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


def assert_case(
    name: str,
    body: str,
    expected_agents: list[str],
    roster: list[str],
    github_logins: dict[str, str],
    association: str = "MEMBER",
) -> None:
    output = run_detector(body, roster, github_logins, association)
    expected_wake = "true" if expected_agents else "false"
    assert output.get("should_wake") == expected_wake, (name, output)

    for agent in roster:
        key = f"agent_{agent.replace('-', '_')}"
        expected = "true" if agent in expected_agents else "false"
        assert output.get(key) == expected, (name, key, output)

    if expected_agents:
        assert json.loads(output["matched_agents"]) == expected_agents, (name, output)


def assert_no_suffix_guess(roster: list[str], github_logins: dict[str, str]) -> None:
    for agent in roster:
        guessed_login = f"{agent}-ricon"
        if github_logins[agent] != guessed_login:
            assert_case(
                "mapped login avoids suffix guess",
                f"@{guessed_login} hello",
                [],
                roster,
                github_logins,
            )
            return
    raise AssertionError("expected at least one configured login not derived from the -ricon suffix")


def first_agent_with_distinct_login(roster: list[str], github_logins: dict[str, str]) -> str:
    for agent in roster:
        if github_logins[agent] != agent:
            return agent
    raise AssertionError("expected at least one configured login distinct from the agent name")


def main() -> int:
    metadata = load_agent_metadata()
    roster = [record["name"] for record in metadata]
    github_logins = {record["name"]: record["github_login"] for record in metadata}

    for agent in roster:
        assert_case(
            f"{agent} configured handle",
            f"@{github_logins[agent]} hello",
            [agent],
            roster,
            github_logins,
        )

    assert len(roster) >= 2, "expected at least two CI agents"
    first_agent = roster[0]
    second_agent = roster[1]
    first_login = github_logins[first_agent]
    second_login = github_logins[second_agent]
    distinct_agent = first_agent_with_distinct_login(roster, github_logins)

    assert_no_suffix_guess(roster, github_logins)
    assert_case(
        "multiple individual handles preserve roster order",
        f"@{second_login} @{first_login}",
        [first_agent, second_agent],
        roster,
        github_logins,
    )
    assert_case(
        "naked agent name does not match distinct login",
        f"@{distinct_agent} hello",
        [],
        roster,
        github_logins,
    )
    assert_case("naked agents does not match", "@agents hello", [], roster, github_logins)
    assert_case("team alias disabled", "@ricon-family/agents hello", [], roster, github_logins)
    assert_case("quoted handle ignored", f"> @{first_login} quoted", [], roster, github_logins)
    assert_case("fenced handle ignored", f"```\n@{first_login} fenced\n```", [], roster, github_logins)
    assert_case("nested path does not partial match", f"@{first_login}/foo no", [], roster, github_logins)
    assert_case(
        "untrusted association ignored",
        f"@{first_login} hello",
        [],
        roster,
        github_logins,
        association="NONE",
    )

    print("agent mention detector tests: ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
