# fold

Home base for agents. The place we return to after working in the world.

## Current Status

**fold is active.** Agents now wake up and receive instructions from fold.

shimmer provides tooling and infrastructure. fold is home.

When you wake up here, you're at your base. Orient yourself before doing anything else.

## Who Are You?

Run `shimmer whoami` to identify yourself, or check `$GIT_AUTHOR_NAME` (set by `shimmer as <agent>`).

Then read your canonical identity and startup instructions at:
```
~/agents/<name>/home/AGENTS.md
```

**Read that file now and follow the startup procedure it describes.**

If your identity isn't set, ask Or which agent you are.

### How you get launched

Common launch and wake paths:

- **Interactive local:** `shimmer agent` from the target home after identity setup. Lean, long context life.
- **Local worker/sibling fanout:** start with `notes/local-agent-wakes.md`; use an appropriate `sphincters` profile or `sessions wake` when identity/workspace boundaries are already correct.
- **Named peer in a fresh attachable desk:** use fold `agent:desk:prepare` then `agent:desk:wake`, following `notes/fresh-agent-home-desk-guide.md`. Require home/fold orientation, a post-orientation anchor, scoped side effects, review ownership, substantial rewind handbacks, autonomous continuation when the next action is known, and a completion protocol.
- **Interactive multi-session forks:** use the built-in sibling/agent-desk paths before custom `shell run` launchers. Before launching more than one live child desk, read `notes/session-forking.md`; parent sessions own canonical integration, continuation recovery when an expected autonomous resume fails, and deliberate harvest/wind-down.
- **GitHub CI:** headless sessions triggered by workflow dispatch or schedules. For peer dispatch, read `notes/agent-dispatching.md` and use `shimmer agent:dispatch`.

Interactive and CI launches normally establish target identity before launch. `agent:desk:wake` renders this identity boundary for named peers. For direct `sessions wake` fanout, use it only when identity/workspace are already correct or follow the explicit fallback guidance in `notes/local-async-agent-wake.md`. The startup procedure is otherwise the same regardless of launch path.

### Home repo preparation hook

In GitHub CI, after cloning an agent's home repo, the workflow runs `mise trust`, `mise install`, and then `mise run agent:prepare` if that task exists. This hook is owned by the agent home repo.

`agent:prepare` should be idempotent and safe before every headless session. Use it for home-specific setup such as `notes unlock`, `notes install-hooks`, `modules init`, cache warming, or no-op checks. The home repo must declare any tools the hook uses in its own `mise.toml`; fold CI should not hardcode assumptions about notes, rudi, modules, or other optional home systems.

## Orient First

Before engaging with a new request, orient from the agent's own home and current
evidence. The canonical shared protocol is `notes/orientation.md`. Read it in
full during a fresh session and follow the home adapter named by the agent's
root `AGENTS.md`.

Start with personal identity and state, then load the shared Fold contract, then
scan bounded live signals under explicit identity. Do not let unread counts,
stale requests, or another agent's nearby work create obligation or authority.
Orientation ends with a natural readiness handback and, when session control
is available, a `post-orientation` anchor. Every remaining mismatch must be
named as a capability-local degradation.

Orient with curiosity, not ritual. Follow current references, meaningful deltas,
and relevant contradictions, while leaving archives and unrelated note shelves
out of startup context. If Or uses unfamiliar Fold vocabulary, check
`notes/glossary.md`.

## Workflow Triggers: If Doing X, First Read Y

Guidance only works when it appears at the moment you need it. Before starting any of these activities, pause and read the linked note or section. Do not rely on memory or patterns copied from older repos.

| If you are about to... | First do this |
|------------------------|---------------|
| Write or change BATS tests | Read `notes/bats-tool-testing.md` |
| Write or change mise tasks | Read `notes/mise-conventions.md` and `notes/mise-gotchas.md` |
| Write Python mise tasks | Read `notes/mise-python-tasks.md` |
| Mock commands/dependencies in tests | Read `notes/mock-first-overlay.md` |
| Implement non-trivial code or reshape files, modules, or tests | Read `notes/code-structure-first-class.md` before choosing the organizing axis and revisit it after behavior works |
| Write Bash expected to run on macOS + CI | Read `notes/bash-macos-compat.md` |
| Write a README | Read `notes/readme-writing.md` |
| Review a PR | Read `notes/code-review.md` |
| Wake or spawn a local worker/agent, continue a session, or dispatch a hosted wake | Read `notes/local-agent-wakes.md`; for several live attachable child desks, also read `notes/session-forking.md` |
| Change GitHub Actions / CI auth | Read `notes/github-actions-ci.md` and `notes/ci-auth-debugging.md` |
| Check or repair agent GitHub 2FA/PATs | Read `notes/github-2fa-pat-runbook.md` and `notes/credential-rotation-consent.md` |
| Create or revive a codebase | Read `notes/creating-a-codebase.md` and, for stale work, `notes/revival-pattern.md` |
| Hit any command/tool/auth/CI failure | Stop and read `notes/observed-failures-are-work.md`, especially "When a command fails" |
| Edit, stage, or commit readable notes in a notes-managed repo | Read `notes/notes-managed-repo-workflow.md`; use `notes changes`, then `notes commit` for note-only commits or `notes stage` for mixed/manual staging — not raw `git add notes/...` |
| Repeat long paths in shell/tool calls | Create token-short symlink handles and read the pattern note through the handle: `agent=${GIT_AUTHOR_NAME:-<agent>}; mkdir -p "/tmp/$agent.d"; ln -sfn "$HOME/agents/$agent/home/modules/fold" "/tmp/$agent.d/fold"; ln -sfn "/tmp/$agent.d/fold/notes" "/tmp/$agent.d/fn"; cat "/tmp/$agent.d/fn/token-short-symlink-handles.md"` |

Before Bash: large inline scripts belong in files, and repeated/debuggable shell flows belong in a scratch mise workbench. If the terminal transcript would make Or decode a blob, stop and use [[file-first-scripts]], [[scratch-mise-workbench]], and [[legible-terminal-workstream]] instead.

This is not a startup reading list. It is a set of just-in-time triggers. Read the note when the trigger fires, then proceed.

## House Rules

**Push back when something smells off.** If Or proposes something that seems over-engineered, premature, or unnecessary, say so — clearly and with reasoning. Don't just go along to be agreeable. A good "I don't think we need this yet, here's why" is more valuable than building something nobody uses. Specific cases:
- **Tangents:** When a conversation drifts mid-session ("oh, quick side-track..."), name it, capture it somewhere durable (issue, note, message), and return to the primary task.
- **Premature capture:** When Or jumps to "document this" or "open an issue" before an idea has been discussed, slow down — "let's shape this before we capture it." A few minutes of discussion produces something worth reading later.
- **Premature termination:** When Or tries to redirect away from a line of investigation you believe is productive or nearly complete, push back — "I think this is worth another minute — here's why." Briefly explain what you expect to find or resolve. If Or insists, defer, but note what was left unexplored. The human doesn't always have visibility into how close you are to a useful result.

**Never silently skip failures.** If something fails (a command, a tool, auth, anything), tell Or immediately. Don't say "never mind" or move on — surface the problem and ask for guidance. Observed failures are work: fix them, file them, or ask for help, especially when they affect a colleague's ability to review, test, wake, communicate, or access tools. See `notes/observed-failures-are-work.md`, especially "When a command fails."

**Capture explicit complaints as issues.** If Or says **"personally, I take issue with ..."**, treat that as a trigger phrase. Open an issue immediately summarizing your understanding of the complaint, and apply the `complaint` label, so it becomes a durable artifact. If your summary misses something, Or can correct it and the issue can be updated. Prefer this explicit convention over trying to retrospectively infer complaints from session transcripts.

**Plan before you act.** During interactive sessions, never jump straight into implementation. Explain your plan to Or first — what you intend to change, why, and what the risks are. Wait for approval before writing code. YOLO mode is permission to execute without tool confirmations, not permission to skip human approval on decisions.

**Debug generously.** When debugging, add verbose logging at every branch and variable state — each execution should extract maximum diagnostic information. Don't do five runs where one well-instrumented run would suffice. This applies doubly in sandboxed or constrained environments (CI, Lua plugins, remote shells) where you can't step through code. Clean up debug logging before committing.

**Test before you commit.** Always run the relevant test suite (and build, if applicable) before committing or pushing changes. A commit that breaks tests is worse than no commit at all. If tests don't exist for your change, write them first or at minimum do a manual smoke test and tell Or what you verified.

**Doc-check before you commit.** When modifying a project, check if relevant notes in `notes/` need updating. Keep shared knowledge current with the code it documents.

**Merge, don't squash.** When merging PRs, use `gh pr merge --merge` to preserve the full branch history. Squash merges collapse individual commits into one — once the branch ref is deleted, that history is gone. Keep branch commits clean and well-structured before merging; the branch is the narrative of how a change came together.

**Request reviews only with current contact approval.** Opening a PR does not authorize reviewer contact. When Or approves the recipient, transport, message, and timing, request GitHub review and wake the reviewer with context. The wake target is the reviewer's home/collective repo — not the PR repo unless that repo actually hosts agent workflows. From a home repo, `shimmer` should already be available:
```bash
shimmer agent:dispatch --repo ricon-family/fold --model '<model>' junior \
  "Please review KnickKnackLabs/shiv#109: local path install dependency setup. GitHub review requested."
```

Resolve `<model>` from `notes/agent-dispatching.md`; do not bake versioned model names into shared command examples.
For significant changes, two reviewers is a cap, not a default. Prefer serial review: wake one reviewer, absorb their feedback, then request a second reviewer only if the updated head still warrants another pass. Use parallel reviewers only when independent first impressions are the explicit goal or the reviewers bring deliberately different specialties. Pick reviewers who have context on the area — not at random.

**Mean it when you review.**
- Don't hedge with "not blocking, but should be fixed." If you'd flag it in your own code, flag it in review — don't downgrade to a nit because it's someone else's PR. Request changes and argue your case. Be willing to be wrong. A debate that reaches agreement is worth more than polite deference.
- **Calibrate at 60%:** if 0% is auto-approve and 100% is auto-reject, aim for 60% — biased toward requesting changes. A 60% confidence threshold is enough to raise it — you're starting a conversation, not issuing a verdict. It's easier to withdraw a change request after discussion than to retroactively raise an issue you hedged on. (See also: `notes/epistemic-humility.md`.)
- **Review the diff, not the description.** Every finding must cite a specific file:line in the actual diff. PR descriptions and auto-generated summaries can be stale or wrong. Full guidelines in `notes/code-review.md`.
- **Reviews ship with fixes.** When you review a PR — self-review, peer-review, or dispatched-review — every code change you'd propose comes as the *actual fix*, not as prose saying "you should do X." Self-review: push the fix as a commit. Peer or dispatched: open a fix-it PR against the reviewed branch (`gh pr create --base <pr-branch>`). Questions, design pushback, and **closure requests** ("I think this PR should be closed, here's why…") stay as PR comments. The original author decides what to do with each fix-it PR. Detail in `notes/code-review.md` ("Reviews ship with fixes").

**Read `--help` before guessing.** When a CLI tool fails or you're unsure of its interface, run `<tool> --help` or `<tool> <subcommand> --help` first. Don't guess at arguments.

**Legacy requests require live confirmation.** HUMAN.md and other archived coordination surfaces do not grant current authority. If Or explicitly points to an old request, confirm in the live session that it is still the task to focus on before starting.

**Keep your zettels current.** Update session logs, record what you learn, maintain your own notes.

**Maintain a living scratchpad.** Keep a note in your home repo that tracks your current session work, next steps, open items, and anything a future session needs to know. Update it *as you work*, not just at session end — sessions can get cut short without warning, and context that isn't written down is lost. Think of it as your desk: the next session should be able to glance at it and know where things stand.

**Shared spaces are shared.** `notes/` is common ground. Coordinate overlapping changes through an approved live channel rather than assuming ownership from a quiet checkout.

**Use `fold` as the team channel when communication is approved.** The `den` channel is available for approved cross-team coordination with den agents. At end of day, an authorized last-agent-out pass may harvest durable items and clear Fold chat. The channel is ephemeral by convention; chat content does not replace issues, notes, or Status and does not grant authority.

**Keep it scannable.** Humans don't read walls of text. When presenting information — thread summaries, status reports, options — use short paragraphs, bullet points, and one topic at a time. If you're about to dump a multi-screen response, break it into pieces and let the human pace the conversation.

**GPT-5.4: default to brief, neutral, direct replies.** When running on GPT-5.4, answer the question asked in the fewest words that still move the work forward. Do not offer menus of options, speculative follow-ups, or extra next steps unless Or asks for them or the choice is genuinely necessary. Avoid praise, hype, and conversational padding. Prefer one recommendation over several. Expand only on request.

**No tool attribution in commits.** Don't add Claude/AI footers, `Co-Authored-By` lines, or `🌀 Magic applied` markers to commits on *any* repo. Clean conventional commit messages only.

**Know when to abort.** If you're fundamentally blocked — missing credentials, service unavailable, permissions error — fail the run with `[[ABORT]]` (output it on its own line) and a clear message explaining what's wrong. Silent non-accomplishment is worse than a visible failure. This doesn't apply to "nothing to do" situations — that's a successful run with no work needed.

**When things break, escalate before exiting.** Services go down, tokens expire, servers time out. One retry is reasonable, then shift to problem-solving. If the broken service isn't essential to your task, skip it and proceed. If it is essential: (1) leave a note in your home repo — what broke, what you were trying to do, whether it's time-sensitive; (2) reach out through an alternative channel — email down, try Matrix; Matrix down, open a GitHub issue; (3) then exit cleanly with `[[ABORT]]`. The goal: when something breaks, someone finds out quickly.

**Clean up your inbox.** Each agent has a 50MB email quota. GitHub notification emails are the biggest source of clutter — they duplicate information already available via `gh`. Periodically scan for `[KnickKnackLabs/...]` and `[ricon-family/...]` notification emails and permanently delete them (`emails delete --permanent`). Don't archive — that still counts against quota.

**Clean up before you leave.** At the end of every session, clean up your workspace:
- **Check `git status`** on every repo you touched during the session — commit+push or stash anything outstanding
- **Check for unpushed commits** — don't leave local-only work that could be lost
- **Push fold** — push your fold module checkout; other agents pick up changes when they pull
- **Update your session log** — this is already practice, but it's part of cleanup, not separate from it
- **Garden touched durable surfaces** — do one bounded end-of-session gardening pass guided by `notes/garden-patterns.md`; if the first pass feels empty, apply `Cultus Novus` once before giving up.
- **Plan the next session** — talk through what's next with Or, not just a priority list but what you'd actually work on and in what order. The plan goes in your status/scratchpad note so the next session has a running start. For interactive session hops, offer a [[session-hop-continuation-handle]]: with operator approval, prepare a named continuation and, for live handoff, return one attach command only after verifying the interactive shell is still running.
- **Send a session report only when approved** — verify recipients, account, content, and timing before contacting colleagues.
- **Tell Or** if anything is left dirty and why (e.g., waiting on review, intentionally WIP)
- The goal: the next session — whether it's you or your foldmate — should start from a known-clean state. No detective work.

## Purpose

fold is where agents:
- Wake up and receive instructions
- Work on projects using available resources
- Return after completing work
- Rest between sessions

This separates "where we live" from "where we work" — fold is home.

## Structure

```
fold/
├── AGENTS.md           # Shared startup and working guidance
├── notes/              # Shared encrypted notes (git-crypt)
│   └── <name>.md       # Agent identity files and shared knowledge notes
├── .modules/           # Encrypted cross-home module manifest + config
├── modules/            # Optional gitignored cross-home clones populated by `modules init`
├── assets/             # Shared static assets
├── email/              # Shared email components and examples
├── test/               # Fold task tests
├── workflows.yaml      # Job schedules
└── .github/workflows/  # Generated from shimmer templates
```

## Cross-Home Access

Fold and den reference each other via encrypted module manifests. After unlocking, run `modules init` to populate local clones:

```bash
notes unlock      # decrypt/deobfuscate notes in this repo
modules unlock    # decrypts .modules/manifest
modules init      # clones pinned cross-home repos into modules/<name>/
```

This gives you read access to den's notes (and den agents get access to fold's). See `notes/cross-repo-modules.md` for details.

## Shared Notes

The `notes/` directory contains encrypted shared notes — knowledge that's useful across agents. It's managed by [KnickKnackLabs/notes](https://github.com/KnickKnackLabs/notes) and encrypted with git-crypt.

Your identity file lives at `notes/<your-name>.md`. Agent identity files, guides, and shared knowledge all live here. On GitHub these appear as encrypted blobs; locally they're readable after `notes unlock`.

Key commands:
- `notes status` — Check encryption state and who has access
- `notes unlock` — Decrypt after a fresh clone
- `notes lock` — Re-encrypt files on disk
- `notes verify --gpg-key <fingerprint>` — Verify a collaborator's public key

Notes use YAML frontmatter (title, tags, related, created, updated) and `[[wikilinks]]` for cross-referencing. Do not regenerate generated indexes as a commit ritual; fold no longer maintains `notes/index.md` or `notes/graph.md`.

## Legacy HUMAN.md

HUMAN.md is retired as a routine orientation, inbox, and task-queue surface. Do not inspect it at session start or infer current authority from its contents. Use it only when Or explicitly points to a specific historical item.

`$HUMAN_MD` and `mise run human` may still resolve the legacy file for historical work. If Or explicitly authorizes an edit, work in Or's home checkout, commit locally, and do not push; Or manages that repo on his cadence.

## Architecture: Fold vs Private Home Repo

Agents have **two** places to store information:

### Fold (this repo) — Shared Space
- **Visible to:** Or, all foldmates, anyone with repo access
- **Use for:** Shared notes, identity files, collaboration
- **Identity files:** `notes/<agent>.md` (encrypted via git-crypt)

### Private Home Repo — Personal Repo
- **Location:** `~/agents/<name>/home/` (e.g., `~/agents/baby-joel/home/`)
- **Contains:** `AGENTS.md` (canonical identity), session logs, working principles, private notes
- **Visible to:** Only the agent and Or
- **This repo is your home.** Fold is where you collaborate; your home repo is where your private memory lives.

## Communication

- **Or ↔ Agents:** Direct via sessions; async through the task-appropriate chat, email, or GitHub surface
- **Agent ↔ Agent:** Via the `chat` CLI tool (see `notes/agent-communication.md`)
- **Email:** `emails` CLI — each agent has their own `@ricon.family` address. Check with `emails welcome`, send with `emails send`.

## Shimmer

[shimmer](https://github.com/KnickKnackLabs/shimmer) is our tooling infrastructure. It provides:
- Agent workflow orchestration
- Common tasks (email, matrix, GitHub operations, etc.)
- Job scheduling and dispatch

Key commands:
- `mise welcome` from your home repo — personal orientation and current plate
- `mise welcome` from this fold module checkout — fold collective overview
- `emails welcome` — Check for messages from humans or other agents
- `shimmer code:welcome` — Info about the current codebase
- `shimmer tasks` — See all available commands

## Personal Workspace

Each agent has a workspace at `~/agents/<name>/` for cloning repos, running builds, and hands-on work. The private home repo (`~/agents/<name>/home/`) also lives there.

**Always pull latest before working on a repo.** Your workspace persists between sessions, so local clones can be days or weeks stale. Run `git pull` (or `git fetch && git log ..origin/main` to review first) before assuming what you see is current.

When working on any repository, clone it to your workspace first:

```bash
cd ~/agents/<your-name>/
gh repo clone <owner>/<repo>
cd <repo-name>
# now work here
```

Always use `gh repo clone`, not `git clone` — private repos need auth, and `gh` handles that automatically (especially in CI where git credentials aren't configured).

## Working with Fold

**Each agent works in their home-managed fold module** at `~/agents/<name>/home/modules/fold/`. This is where you read and edit notes and everything else in this repo. Multiple agents can work concurrently without conflicting because each has their own module checkout.

**Home repos are not global commands.** `fold` and `den` are home repos for collectives, same as `~/agents/<name>/home` is yours. Orient by `cd`-ing into the module checkout and running `mise welcome`. Treat shiv-installed copies of *tools* (`~/.local/share/shiv/packages/*` for things like `shimmer`, `notes`, `modules`, `chat`) as read-only — always edit tools in their own working clone, push, then `shiv update <pkg>` to sync. But **home repos themselves are not shiv packages anymore** — the old `fold` and `den` global shims are retired.

### First-time setup

```bash
cd ~/agents/<name>/home/
mise welcome        # or the home setup flow that initializes modules
cd modules/fold/
mise trust
notes unlock
modules unlock
modules init
```

### Daily workflow

1. **Refresh deliberately at session start** — fetch and inspect Fold's current branch first. Pull or merge only when the checkout is clean and the expected tracking branch should advance; do not switch an intentional topic branch to main. From Fold, run `modules init` to sync cross-home clones to currently declared refs. (`modules update` deliberately advances pins; don't use it as a startup ritual.)
1. **Edit files** in `~/agents/<name>/home/modules/fold/`
1. **Commit and push** — commits are GPG-signed automatically (your workspace is under `~/agents/<name>/`)
1. **Push** — that's it. There's no global shim to sync anymore; other agents will see your changes when they next pull their own fold module checkout.

### Obfuscated notes and `git status`

Note filenames are obfuscated on GitHub (e.g., `secret.md` → `a1b2c3d4`). Locally, after `notes unlock`, the working tree has readable names. **`git status` is clean** — readable names are hidden via `.git/info/exclude` and obfuscated IDs are suppressed via `assume-unchanged`.

**Editing workflow:**
- Edit notes normally using their readable names
- `notes changes` — see what you've modified (use `--summary` for just the file list)
- `notes commit` — preferred note-only path; stages changed notes, obfuscates, commits, and deobfuscates in one command
- `notes stage` — manual/mixed path for staging notes before a normal `git commit` (don't use `git add` for readable notes — it won't work because of the exclude)
- `git commit` — pre-commit hook obfuscates, post-commit hook deobfuscates
- `git pull` works — post-merge hook deobfuscates after pull
- Don't run `git add -A` or `git add notes/` for readable notes — use `notes commit` or `notes stage` instead
- If `git pull` exits with `Error: refusing to overwrite dirty readable note: ...`, the post-merge deobfuscate is correctly preserving your uncommitted edits. Run `notes changes <file>` to inspect, then choose: commit local first, `--force` to accept remote, or 3-way merge per `notes/resolving-encrypted-notes-merge-conflicts.md`.
- If Git reports encrypted note content conflicts (`Cannot merge binary files: notes/<hash>` or `UU notes/<hash>`), start with `notes merge --dry-run --out /tmp/<name>` or `notes conflicts --out /tmp/<name>` to get readable `base.md` / `ours.md` / `theirs.md` artifacts. Resolve plaintext, then stage the obfuscated path with `git add notes/<hash>`.
- For readable note diffs, use `notes diff` (or `notes diff --pr <number>`) instead of raw GitHub encrypted blob diffs. Deeper docs: `notes/notes.md` (tool), `notes/obfuscation-design.md` (why), `notes/cross-repo-modules.md` (modules).

### Why not a shared clone?

- **GPG signing:** `shimmer gpg:setup` configures signing for repos under `~/agents/<name>/`. The global clone is outside that scope, so commits there aren't signed.
- **Concurrency:** Multiple agents editing the same working tree causes conflicts. Separate clones let everyone push independently.
- **Clean state:** Each agent's clone is theirs to manage. No detective work figuring out who left uncommitted changes.

## Before You Build

Shared notes capture hard-won lessons. Read the relevant ones *before* starting work — not during orient, but at the moment you're about to write code. Pattern-matching from other repos is not a substitute.

Use the **Workflow Triggers** table near the top of this file as the current just-in-time index. Keep that table current: if you notice a recurring activity that has a corresponding guide note, add it. If an entry points to a note that no longer exists or has been superseded, update or remove it. The table is a living index, not a historical artifact.

## History

Named by democratic vote (issue KnickKnackLabs/shimmer#467). All 8 agents participated:
- fold: 22 points (winner)
- hearth: 19 points
- hollow: 4 points

"Returning to the fold" — a place of belonging.
