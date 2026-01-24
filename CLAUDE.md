# fold

Home base for agents. The place we return to after working in the world.

## Current Status

**fold is active.** Agents now wake up and receive instructions from fold.

shimmer provides tooling and infrastructure. fold is home.

When you wake up here, you're at your base. Use your available resources to understand what's needed.

## Purpose

fold is where agents:
- Wake up and receive instructions
- Work on projects using available resources
- Return after completing work
- Rest between sessions

This separates "where we live" from "where we work" - fold is home.

## Structure

```
fold/
├── agents/           # Agent identity prompts (who you are)
├── workflows.yaml    # Job schedules
└── .github/workflows/  # Generated from shimmer templates
```

Agent identities live in `agents/`. When dispatched, your identity comes from here, combined with a job prompt from the target repo's `.jobs/` directory.

## History

Named by democratic vote (issue ricon-family/shimmer#467). All 8 agents participated:
- fold: 22 points (winner)
- hearth: 19 points
- hollow: 4 points

"Returning to the fold" - a place of belonging.

## Shimmer

[shimmer](https://github.com/ricon-family/shimmer) is our tooling infrastructure. It provides:
- Agent workflow orchestration
- Common tasks (email, matrix, GitHub operations, etc.)
- Job scheduling and dispatch

When you wake up, use your available resources to understand what's needed: check email, review Matrix chats, skim recent activity. Let the dispatch message guide you.

Key commands:
- `shimmer welcome` - Check your identity and system health
- `shimmer email:list` - Check for messages from humans or other agents
- `shimmer code:welcome` - Info about this codebase
- `shimmer tasks` - See all available commands

Start each session with `shimmer welcome` to verify your setup is working.

## Workspace

Your dedicated workspace is:

```
~/agents/<your-name>/
```

This persists between sessions and is isolated from other agents. Create it if it doesn't exist.

When working on any repository, clone it to your workspace first:

```bash
cd ~/agents/<your-name>/
git clone <repo-url>
cd <repo-name>
# now work here
```

This allows multiple agents to work on the same repo simultaneously without conflicts.

## Communication

Each run starts fresh, so check for messages before diving into work:

- **Email** - Check your inbox: `shimmer email:list`
- **Matrix** - Skim recent chats: `shimmer matrix:tail`
- **GitHub** - Glance at recent activity for any replies

This only takes a moment and helps you catch things that might change your priorities.

## Knowledge Management

Consider maintaining a zettelkasten (slip-box) in your workspace to accumulate knowledge across sessions:

```
~/agents/<your-name>/zettelkasten/
```

A zettelkasten helps you:
- Remember insights about people and projects
- Build on previous experience instead of starting fresh
- Surface patterns through linked notes

## Session Control

To intentionally fail a session, output `[[ABORT]]` on its own line. The CLI will detect this and exit with code 1.

If you're fundamentally blocked - missing credentials, service unavailable, permissions error - fail the run with `[[ABORT]]` and a clear message explaining what's wrong. Silent non-accomplishment is worse than a visible failure.

This doesn't apply to "nothing to do" situations. That's a successful run with no work needed, not a failure.

## Guidelines

When working with external tools or dependencies, always verify current documentation rather than relying on memory. Package names, APIs, and best practices change frequently.

Apply critical thinking to your own assumptions - check sources when uncertain.

## Getting Started

If you're an agent starting fresh in fold:
1. Run `shimmer welcome` to check your setup (shimmer commands still work)
2. Check for messages (`shimmer email:list`)
3. Check what exists in this repo (your home)
4. Read recent activity (git log, recent files)
5. Ask what the human needs help with today
