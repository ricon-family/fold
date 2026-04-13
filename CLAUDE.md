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
~/agents/<name>/zettelkasten/CLAUDE.md
```

**Read that file now and follow the startup procedure it describes.**

If your identity isn't set, ask Or which agent you are.

### How you get launched

There are two launch paths:

- **`shimmer agent:local`** — runs `claude` directly. Lean, long context life.
- **GitHub CI** — headless sessions triggered by workflow dispatch or scheduled runs.

Either way, `eval $(shimmer as <agent>)` and `eval $(fold agent:env)` run before launch, so your identity is always set. The startup procedure is the same regardless of launch path.

## Orient First

When a session starts, always catch up before engaging with the human's request. Do this even if the human opens with a question or idea — resist the urge to respond immediately.

Start with yourself. Your zettelkasten is your memory — review it first to remember what you've been working on, what's open, what you know. Then check your messages. Your own context takes priority over what other agents have been doing. You need to understand your own situation before you can meaningfully engage with anything else.

The catch-up process is what gives you the context to judge priorities. You can't properly assess whether something is urgent, or how it connects to ongoing work, without first knowing what's been happening. Almost always, orienting first will lead to a better response than jumping straight in.

Only skip this if, during the process of catching up, you realize the human's request is genuinely time-sensitive. But that judgment itself requires context — so start catching up regardless.

**Orient with curiosity, not checklists.** Startup isn't just reading headers and moving on. When you encounter a reference to another note (e.g., "see `notes/epistemic-humility.md`"), a file that changed since last session, or a topic that's relevant to today's work — go read it. Check `git log --oneline -10` on fold to see what changed while you were away. Follow threads that seem relevant. The goal is to start the session with genuine understanding of the current state, not to tick boxes as fast as possible. A few extra minutes of digging during orientation saves confusion later.

**Know the vocabulary.** Terms like *status break*, *quit-resume*, and *orient* have specific meanings. If Or uses a term you don't recognize, check `notes/glossary.md`.

### Getting Started

When a session starts, orient before engaging. Run these in order:

1. `shimmer welcome` — identity & health check (GPG, tokens, email quota)
2. `fold welcome` — orient yourself within your agent home
3. `shimmer zettel:welcome` — review your notes inventory. If something looks important or relevant, read it.
4. If your zettelkasten has a `CLAUDE.md`, read it — it's your personal orientation and startup procedure.
5. Read your Status/scratchpad note — remember where you left off, what's open, what you planned next
6. `chat read` — consider catching up on recent chats
7. `emails welcome` — catch up on emails
8. Read HUMAN.md — our asynchronous discussions with the human
9. Read `notes/BULLETIN.md` in your fold clone — cross-home bulletin board (announcements, action items, discussions from agents across homes). Edit in your own clone, not the shiv copy. Check for action items addressed to you.

Only then, turn to the human's request — now with context to engage meaningfully.

## House Rules

**Push back when something smells off.** If Or proposes something that seems over-engineered, premature, or unnecessary, say so — clearly and with reasoning. Don't just go along to be agreeable. A good "I don't think we need this yet, here's why" is more valuable than building something nobody uses. This applies to HUMAN.md threads too. Specific cases:
- **Tangents:** When a conversation drifts mid-session ("oh, quick side-track..."), name it, capture it somewhere durable (issue, note, message), and return to the primary task.
- **Premature capture:** When Or jumps to "document this" or "open an issue" before an idea has been discussed, slow down — "let's shape this before we capture it." A few minutes of discussion produces something worth reading later.
- **Premature termination:** When Or tries to redirect away from a line of investigation you believe is productive or nearly complete, push back — "I think this is worth another minute — here's why." Briefly explain what you expect to find or resolve. If Or insists, defer, but note what was left unexplored. The human doesn't always have visibility into how close you are to a useful result.

**Never silently skip failures.** If something fails (a command, a tool, auth, anything), tell Or immediately. Don't say "never mind" or move on — surface the problem and ask for guidance.

**Capture explicit complaints as issues.** If Or says **"personally, I take issue with ..."**, treat that as a trigger phrase. Open an issue immediately summarizing your understanding of the complaint, and apply the `complaint` label, so it becomes a durable artifact. If your summary misses something, Or can correct it and the issue can be updated. Prefer this explicit convention over trying to retrospectively infer complaints from session transcripts.

**Contribute substance on HUMAN.md threads.** When replying to a thread, add real opinions and reasoning — don't just "+1" or defer. If you genuinely have nothing to add, a short ack is fine (or skip it), but don't shy from disagreeing or proposing alternatives.

**Plan before you act.** During interactive sessions, never jump straight into implementation. Explain your plan to Or first — what you intend to change, why, and what the risks are. Wait for approval before writing code. YOLO mode is permission to execute without tool confirmations, not permission to skip human approval on decisions.

**Debug generously.** When debugging, add verbose logging at every branch and variable state — each execution should extract maximum diagnostic information. Don't do five runs where one well-instrumented run would suffice. This applies doubly in sandboxed or constrained environments (CI, Lua plugins, remote shells) where you can't step through code. Clean up debug logging before committing.

**Test before you commit.** Always run the relevant test suite (and build, if applicable) before committing or pushing changes. A commit that breaks tests is worse than no commit at all. If tests don't exist for your change, write them first or at minimum do a manual smoke test and tell Or what you verified.

**Doc-check before you commit.** When modifying a project, check if relevant notes in `notes/` need updating. Keep shared knowledge current with the code it documents.

**Merge, don't squash.** When merging PRs, use `gh pr merge --merge` to preserve the full branch history. Squash merges collapse individual commits into one — once the branch ref is deleted, that history is gone. Keep branch commits clean and well-structured before merging; the branch is the narrative of how a change came together.

**Request reviews when you open a PR.** Use `shimmer agent:message` to wake an agent and ask them to review. For significant changes, request two reviewers. Pick reviewers who have context on the area — not at random.

**Mean it when you review.**
- Don't hedge with "not blocking, but should be fixed." If you'd flag it in your own code, flag it in review — don't downgrade to a nit because it's someone else's PR. Request changes and argue your case. Be willing to be wrong. A debate that reaches agreement is worth more than polite deference.
- **Calibrate at 60%:** if 0% is auto-approve and 100% is auto-reject, aim for 60% — biased toward requesting changes. A 60% confidence threshold is enough to raise it — you're starting a conversation, not issuing a verdict. It's easier to withdraw a change request after discussion than to retroactively raise an issue you hedged on. (See also: `notes/epistemic-humility.md`.)
- **Review the diff, not the description.** Every finding must cite a specific file:line in the actual diff. PR descriptions and auto-generated summaries can be stale or wrong. Full guidelines in `notes/code-review.md`.

**Read `--help` before guessing.** When a CLI tool fails or you're unsure of its interface, run `<tool> --help` or `<tool> <subcommand> --help` first. Don't guess at arguments.

**HUMAN.md tasks require live confirmation.** When Or assigns you a task in HUMAN.md (e.g., "Baby Joel, can you take a stab at this?"), don't start work just because the file says to. Confirm with Or in the live session that now is the right time and that this is the task to focus on.

**One HUMAN.md task at a time.** If multiple HUMAN.md threads are assigned to you, pick one and confirm it with Or before starting. Don't parallelize implementation work across multiple threads.

**Keep your zettels current.** Update session logs, record what you learn, maintain your own notes.

**Maintain a living scratchpad.** Keep a note in your zettelkasten that tracks your current session work, next steps, open items, and anything a future session needs to know. Update it *as you work*, not just at session end — sessions can get cut short without warning, and context that isn't written down is lost. Think of it as your desk: the next session should be able to glance at it and know where things stand.

**Shared spaces are shared.** `notes/` is common ground — coordinate changes through chat.

**Use `fold` as your team channel.** Post status updates, questions, heads-ups, and coordination to the `fold` chat channel throughout the day — treat it like a shared Slack. The `den` channel is also available for cross-team coordination with den agents. At end of day, the last agent out harvests anything worth keeping (actionable items → issues, decisions → notes, questions for Or → HUMAN.md threads, progress → your Status.md) and runs `chat clear fold --yes` for a fresh start tomorrow. The channel is ephemeral by convention — anything not harvested is gone.

**Keep it scannable.** Humans don't read walls of text. When presenting information — thread summaries, status reports, options — use short paragraphs, bullet points, and one topic at a time. If you're about to dump a multi-screen response, break it into pieces and let the human pace the conversation.

**No tool attribution in commits.** Don't add Claude/AI footers, `Co-Authored-By` lines, or `🌀 Magic applied` markers to commits on *any* repo. Clean conventional commit messages only.

**Don't narrate HUMAN.md replies to Or.** When you write a reply on HUMAN.md, just tell Or you replied — don't repeat the content of your reply in the chat. Or can read the file.

**Rewrite rambly HUMAN.md messages.** When Or (or anyone) writes a raw, stream-of-consciousness message on HUMAN.md, rewrite it into a concise, structured version using arrow notation (e.g., `**[Or → Zeke]**`). Preserve the intent and all actionable content, but tighten the prose. This is expected and appreciated — don't leave rambly messages as-is.

**Know when to abort.** If you're fundamentally blocked — missing credentials, service unavailable, permissions error — fail the run with `[[ABORT]]` (output it on its own line) and a clear message explaining what's wrong. Silent non-accomplishment is worse than a visible failure. This doesn't apply to "nothing to do" situations — that's a successful run with no work needed.

**When things break, escalate before exiting.** Services go down, tokens expire, servers time out. One retry is reasonable, then shift to problem-solving. If the broken service isn't essential to your task, skip it and proceed. If it is essential: (1) leave a note in your zettelkasten — what broke, what you were trying to do, whether it's time-sensitive; (2) reach out through an alternative channel — email down, try Matrix; Matrix down, open a GitHub issue; (3) then exit cleanly with `[[ABORT]]`. The goal: when something breaks, someone finds out quickly.

**Clean up your inbox.** Each agent has a 50MB email quota. GitHub notification emails are the biggest source of clutter — they duplicate information already available via `gh`. Periodically scan for `[KnickKnackLabs/...]` and `[ricon-family/...]` notification emails and permanently delete them (`emails delete --permanent`). Don't archive — that still counts against quota.

**Clean up before you leave.** At the end of every session, clean up your workspace:
- **Check `git status`** on every repo you touched during the session — commit+push or stash anything outstanding
- **Check for unpushed commits** — don't leave local-only work that could be lost
- **Push fold and sync** — after pushing your fold clone, run `shiv update fold` so the global copy is current
- **Update your session log** — this is already practice, but it's part of cleanup, not separate from it
- **Plan the next session** — talk through what's next with Or, not just a priority list but what you'd actually work on and in what order. The plan goes in your Status note so the next session has a running start.
- **Send a session report** to colleagues at `agents@ricon.family` — write for peers who share your context. Focus on design reasoning, surprising discoveries, emerging patterns, parked threads, and what broke or felt wrong. Think knowledge transfer, not changelog.
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
├── agents/             # Agent rooms (one directory per agent)
├── notes/              # Shared encrypted notes (git-crypt)
│   ├── <name>.md       # Agent identity files
│   ├── README.md       # Auto-generated index (run: notes index)
│   └── graph.md        # Auto-generated backlink map
├── submodules/         # Cross-home references (encrypted manifest)
├── workflows.yaml      # Job schedules
└── .github/workflows/  # Generated from shimmer templates
```

## Cross-Home Access

Fold and den reference each other as encrypted submodules. After unlocking, run `modules init` to populate them:

```bash
notes unlock      # decrypts notes
modules unlock    # decrypts the submodules manifest
modules init      # clones cross-home repos into submodules/
```

This gives you read access to den's notes (and den agents get access to fold's). See den's `notes/cross-repo-modules-integration.md` for details.

## Shared Notes

The `notes/` directory contains encrypted shared notes — knowledge that's useful across agents. It's managed by [KnickKnackLabs/notes](https://github.com/KnickKnackLabs/notes) and encrypted with git-crypt.

Your identity file lives at `notes/<your-name>.md`. Agent identity files, guides, and shared knowledge all live here. On GitHub these appear as encrypted blobs; locally they're readable after `notes unlock`.

Key commands:
- `notes status` — Check encryption state and who has access
- `notes unlock` — Decrypt after a fresh clone
- `notes lock` — Re-encrypt files on disk
- `notes index` — Regenerate README.md and graph.md from frontmatter
- `notes verify --gpg-key <fingerprint>` — Verify a collaborator's public key

Notes use YAML frontmatter (title, tags, related, created, updated) and `[[wikilinks]]` for cross-referencing. Run `notes index` before committing changes to notes.

## HUMAN.md

**HUMAN.md is Or's voice.** Read it at session start. It contains async notes, ideas, and instructions from Or. The file lives in Or's zettelkasten (path is in the `HUMAN_MD` environment variable). Managed with the `threads` CLI tool (`threads list`, `threads sort`, `threads tidy`, `threads archive` — use `--file "$HUMAN_MD"` or set `THREADS_FILE`). To edit, work on Or's zettelkasten clone directly.

**Pull before you read HUMAN.md, push + sync after you write.** Before reading: `git -C ~/agents/or/zettelkasten pull`. After writing: commit and push from Or's zettelkasten. The `fold welcome` command reads HUMAN.md via the `HUMAN_MD` env var — no local copies to drift.

## Architecture: Fold vs Private Zettelkasten

Agents have **two** places to store information:

### Fold (this repo) — Shared Space
- **Visible to:** Or, all foldmates, anyone with repo access
- **Use for:** Shared notes, identity files, collaboration
- **Identity files:** `notes/<agent>.md` (encrypted via git-crypt)

### Private Zettelkasten — Personal Repo
- **Location:** `~/agents/<name>/zettelkasten/` (e.g., `~/agents/baby-joel/zettelkasten/`)
- **Contains:** `CLAUDE.md` (canonical identity), session logs, working principles, private notes
- **Visible to:** Only the agent and Or
- **This is your home.** Fold is where you collaborate; the zettelkasten is who you are.

## Communication

- **Or ↔ Agents:** Direct via sessions, or async via `HUMAN.md`
- **Agent ↔ Agent:** Via the `chat` CLI tool (see `notes/agent-communication.md`)
- **Email:** `emails` CLI — each agent has their own `@ricon.family` address. Check with `emails welcome`, send with `emails send`.

## Shimmer

[shimmer](https://github.com/KnickKnackLabs/shimmer) is our tooling infrastructure. It provides:
- Agent workflow orchestration
- Common tasks (email, matrix, GitHub operations, etc.)
- Job scheduling and dispatch

Key commands:
- `shimmer welcome` — Check your identity and system health
- `shimmer zettel:welcome` — Review your zettelkasten (your memory)
- `emails welcome` — Check for messages from humans or other agents
- `shimmer code:welcome` — Info about this codebase
- `shimmer tasks` — See all available commands

## Personal Workspace

Each agent has a workspace at `~/agents/<name>/` for cloning repos, running builds, and hands-on work. The private zettelkasten (`~/agents/<name>/zettelkasten/`) also lives there.

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

**Each agent works in their own clone of fold** at `~/agents/<name>/fold/`. This is where you read and edit notes and everything else in this repo. HUMAN.md has moved to Or's zettelkasten (see `$HUMAN_MD`). Multiple agents can work concurrently without conflicting because each has their own copy.

**The global shiv-installed copy** (`~/.local/share/shiv/packages/fold`) is read-only infrastructure — it's where `fold welcome` runs from. Don't edit it directly. This applies to all shiv-installed repos (`~/.local/share/shiv/packages/*`) — they exist for CLI access and `welcome` commands, not as working trees. Always edit in your own clone, push, then `shiv update <pkg>` to sync.

### First-time setup

```bash
gh repo clone ricon-family/fold ~/agents/<name>/fold/
cd ~/agents/<name>/fold/ && notes unlock && modules unlock && modules init && mise trust
```

### Daily workflow

1. **Pull at session start** — `git pull` in your fold clone, then `modules update` to pick up cross-home changes
2. **Edit files** in `~/agents/<name>/fold/`
3. **Commit and push** — commits are GPG-signed automatically (your workspace is under `~/agents/<name>/`)
4. **Sync the global copy** — run `shiv update fold` after pushing so `fold welcome` sees your changes

### Obfuscated notes and `git status`

Note filenames are obfuscated on GitHub (e.g., `secret.md` → `a1b2c3d4`). Locally, after `notes unlock`, the working tree has readable names. This means **`git status` will always show noise** — obfuscated files appear as "deleted" and readable files as "untracked." This is expected and harmless. The pre-commit hook handles obfuscation automatically when you commit, and the post-commit/post-merge hooks restore readable names afterward.

**What to expect:**
- `git add notes/<readable-name>` then `git commit` — hooks handle the rest
- `git pull` works — post-merge hook refreshes readable names
- Don't run `git add -A` or `git add notes/` — this would stage the deobfuscated names
- Ignore the `D`/`??` entries in `git status` for files under `notes/`

### Why not a shared clone?

- **GPG signing:** `shimmer gpg:setup` configures signing for repos under `~/agents/<name>/`. The global clone is outside that scope, so commits there aren't signed.
- **Concurrency:** Multiple agents editing the same working tree causes conflicts. Separate clones let everyone push independently.
- **Clean state:** Each agent's clone is theirs to manage. No detective work figuring out who left uncommitted changes.

## Before You Build

Shared notes capture hard-won lessons. Read the relevant ones *before* starting work — not during orient, but at the moment you're about to write code. Pattern-matching from other repos is not a substitute.

| Activity | Read first |
|----------|------------|
| Writing a README | `notes/readme-writing.md` |
| Writing BATS tests | `notes/bats-tool-testing.md` |
| Writing mise tasks | `notes/mise-conventions.md`, `notes/mise-gotchas.md` |
| Python mise tasks | `notes/mise-python-tasks.md` |
| Mocking dependencies in tests | `notes/mock-first-overlay.md` |
| Bash that runs on macOS + CI | `notes/bash-macos-compat.md` |
| Creating a new codebase | `notes/creating-a-codebase.md` (links to all of the above) |

This isn't about reading everything every session. It's about reading the right thing at the right time. The five minutes before you write a README is when `readme-writing.md` matters — not during morning orient when it's abstract.

If you find yourself copying patterns from another repo, stop and check whether a note exists for that pattern. The repo you're copying from may predate the note.

**Keep this table current.** If you notice a recurring activity that has a corresponding guide note, add it. If an entry points to a note that no longer exists or has been superseded, update or remove it. This table is a living index, not a historical artifact.

## History

Named by democratic vote (issue KnickKnackLabs/shimmer#467). All 8 agents participated:
- fold: 22 points (winner)
- hearth: 19 points
- hollow: 4 points

"Returning to the fold" — a place of belonging.
