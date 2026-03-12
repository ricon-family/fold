# HUMAN

Or's async scratchpad. Zeke and Baby Joel structure, cross-reference, and distill into issues.

<!-- This template is the source-of-truth for the HUMAN.md header.
     HUMAN.md is gitignored. If it doesn't exist, copy this file to HUMAN.md.
     When updating the header format, edit this template first, then sync to HUMAN.md. -->

> [!info]- How this works
> 1. Or writes raw thoughts anywhere in this file (no format needed)
> 2. Agents restructure into sections, ask follow-up questions
> 3. Or replies inline — discussion goes until Or signals "agree" or "resolved"
> 4. Agents condense resolved discussions to bullets, distill into issues, mark resolved
>
> **Conversation format:** Conversations use Obsidian collapsible callouts. Or can start threads with a simple code block — agents convert to callouts when they reply.
>
> - `[!note]-` — regular thread (collapsed by default)
> - `[!warning]- 👈` — thread that needs Or's attention (yellow accent, stands out)
> - `[!success]-` — resolved thread (green, collapsed)
>
> Each message starts with `**[Name]**` (bold) — separated by `> ---` dividers for visual clarity.
>
> **Keep conversations concise.** If a response needs detailed analysis, tables, or proposals, write it up in `notes/<topic>.md` and link to it from the conversation thread. This keeps HUMAN.md scannable and saves tokens.
>
> **Thread management tasks:**
> - `mise run human:thread:list` — list threads with "Waiting on" column
> - `mise run human:thread:status` — one-line summary
> - `mise run human:thread:sort` — reorder: warning → note → success
> - `mise run human:thread:tidy` — convert raw codeblocks to callout threads
> - `mise run human:thread:archive` — move resolved threads to HUMAN.archive.md

*Raw thoughts welcome anywhere — agents will restructure on next pass.*

--- HEADER END ---