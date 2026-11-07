---
name: notion-board
description: >-
  Manage the strukturunion toolbox Development Taskboard on Notion in one
  consistent way. Use when creating/updating tickets, moving status, claiming
  work, or linking a PR to a ticket for the toolbox. The board is the single
  source of truth for project status; this skill keeps every session (and the
  human) using identical fields, statuses, identifiers, and body template.
---

# Notion board — toolbox Development Taskboard

The board ("strukturunion toolbox Development Taskboard") is the **single source
of truth** for what we will do, are doing, and have done. This repo holds only
the *how-we-use-it* (this skill + `docs/ops/notion-workflow.md`) — never the
status itself.

Refer to every piece of work by its **identifier** (`TBX-12`), never by title or
position: "implement TBX-14" is unambiguous and always means this board.

## Environment

```
NOTION_TOKEN        internal-integration token (provided per session; never commit)
NOTION_BOARD_ID     the live board's database id (also accepts NOTION_DATABASE_ID;
                    falls back to the baked DEFAULT_DATABASE_ID only if neither is set)
SSL_CERT_FILE=/root/.ccr/ca-bundle.crt   # when behind the agent proxy
```

## Where the token comes from

This token is needed **only in Claude Code sessions**, never by the toolbox app —
so there is **no service account** to grant and nothing to wire into Cloud Run.

The tooling reads `NOTION_TOKEN` straight from the **environment**. The standing
setup is the `NOTION_TOKEN` variable configured in the **Claude Code web
environment settings** — every session inherits it automatically, so nothing
needs to be pasted. (Environment changes apply at session start; a variable added
mid-session lands in the *next* session, not the current one.)

**Only if it's missing** (the command errors that `NOTION_TOKEN` is not set) does
a session fall back to a token pasted in the opening prompt — export it as
`NOTION_TOKEN` for that session. Either way the token lives only in the session
and is never committed. The board id comes from the `NOTION_BOARD_ID` environment
variable (set in the Claude Code environment settings, alongside `NOTION_TOKEN`),
with the baked `DEFAULT_DATABASE_ID` as a last-resort fallback — so a session that
inherits both vars needs nothing pasted at all.

## Schema (managed by `apply-schema`)

| Property | Type | Role |
|----------|------|------|
| `Name` | title | concise summary (no manual number) |
| `ID` | unique_id, prefix `TBX` | identifier — **added in the Notion UI** (API can't create it) |
| `Status` | select | Kanban column |
| `Type` | select | Bug · Feature · Chore · Infra · Spike |
| `Priority` | select | P0 · P1 · P2 · P3 |
| `Area` | select | Platform · Shell · Storage · OCR · Inbox · Customers · Orders · Invoicing · Dunning · SEPA · Bank · Settings · Infra · Docs · Tool |
| `Owner` | select | Manuel · Claude · Antigravity (who currently holds it) |
| `ClaimedAt` | date | stamped when it enters In Progress |
| `PRUrl` | url | the pull request |
| `Spec` | url | governing `docs/` spec section (Feature tickets) |

**Status (Kanban columns):** `Backlog → Ready → In Progress → In Review → Done`,
plus `Blocked`.

The **page body** holds the story (one template — see `notion-workflow.md`):
`## Problem / Context`, `## Acceptance Criteria` (checkboxes), `## Design / Notes`,
`## Links`, `## Work Log`. Properties are for board views/filtering; the body is
the narrative + dated work log; discussion goes in page comments.

## Lifecycle (human and Claude move tickets identically)

- **Pick up:** `Status=In Progress`, set `Owner`, set `ClaimedAt`=today.
- **Open PR:** `Status=In Review`, set `PRUrl`, add a Work-Log line; the PR title
  references the ID (`TBX-12: …`).
- **Merged + verified:** `Status=Done`.
- **Stuck:** `Status=Blocked` + a Work-Log line stating why.
- Every **Feature** links a `Spec`; every **Bug**'s PR adds a regression test
  (per `TESTING.md`).

## Commands (run from repo root)

```bash
H=.claude/skills/notion-board/notion_board.py

python $H apply-schema          # create/realign properties + select options (admin)
python $H setup-db              # print the live schema

python $H create --title "OCR loses blobs after a day" \
  --type Bug --priority P0 --area Storage --owner Claude \
  --spec https://github.com/.../docs/.../storage.md \
  --body-file ticket.md         # body = the template (markdown subset)

python $H status   <page_id> "In Review"
python $H link-pr  <page_id> https://github.com/strukturunion-mmw/strukturunion-toolbox/pull/NN
python $H list      [--status "In Progress"]
```

## One-time setup recap

1. Notion internal integration → share the board with it (`••• → Connections`).
2. Set `NOTION_TOKEN` once in the Claude Code web environment settings so every
   session inherits it; if it's ever absent, paste a session token in the opening
   prompt and export it instead. It's Claude-Code-only — no service account or
   Cloud Run wiring.
3. `python notion_board.py apply-schema`.
4. **In the Notion UI:** add property `ID`, type *Unique ID*, prefix `TBX`.
5. Fill the board (history backfill + open tickets), then it's authoritative.
