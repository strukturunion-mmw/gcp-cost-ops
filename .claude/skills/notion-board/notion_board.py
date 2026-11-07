#!/usr/bin/env python3
"""Notion board helper for the strukturunion toolbox.

A dependency-free (stdlib only) CLI wrapper around the Notion API so every
session manages the **Development Taskboard** the *same* way: identical fields,
identical status values, identical page-body template, PRs linked consistently.

The board is the single source of truth for project status. This repo keeps only
the *how-we-use-it* (this skill + docs/ops/notion-workflow.md), never the status.

Auth/config from the environment (never commit the token):
  NOTION_TOKEN        internal-integration token (Claude Code env setting; or a
                      session token pasted in the prompt when that's absent)
  NOTION_BOARD_ID     the board's database id (also accepts NOTION_DATABASE_ID;
                      falls back to the known board only if neither is set)
  SSL_CERT_FILE       /root/.ccr/ca-bundle.crt when behind the agent proxy

Schema (managed by `apply-schema`; the `ID` Unique-ID prop is added in the UI):
  Name(title) · ID(unique_id, prefix TBX, UI-only) · Status(select) ·
  Type(select) · Priority(select) · Area(select) · Owner(select) ·
  ClaimedAt(date) · PRUrl(url) · Spec(url)

Status (Kanban columns): Backlog · Ready · In Progress · In Review · Blocked · Done

Subcommands:
  apply-schema             create/realign the managed properties + select options
  setup-db                 print the live schema (verify)
  create ...               create a ticket (properties + body from --body-file)
  status <page_id> <s>     move a ticket to a status
  link-pr <page_id> <url>  attach a PR url (PRUrl)
  list [--status S]        list tickets (optionally filtered)
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import urllib.error
import urllib.request

API = "https://api.notion.com/v1"
NOTION_VERSION = "2022-06-28"
# Fallback board id, used only when neither NOTION_BOARD_ID nor NOTION_DATABASE_ID
# is set in the environment (see _database_id). The env var is the source of truth.
DEFAULT_DATABASE_ID = "9cfc3187a012834fabfe01838bc561a8"

STATUSES = ["Backlog", "Ready", "In Progress", "In Review", "Blocked", "Done"]
TYPES = ["Bug", "Feature", "Chore", "Infra", "Spike"]
PRIORITIES = ["P0", "P1", "P2", "P3"]
AREAS = [
    "Platform",
    "Shell",
    "Storage",
    "OCR",
    "Inbox",
    "Customers",
    "Orders",
    "Invoicing",
    "Dunning",
    "SEPA",
    "Bank",
    "Settings",
    "Infra",
    "Docs",
    "Tool",
]
OWNERS = ["Manuel", "Claude", "Antigravity"]

# The select properties this skill owns (name -> allowed option list).
MANAGED_SELECTS = {
    "Status": STATUSES,
    "Type": TYPES,
    "Priority": PRIORITIES,
    "Area": AREAS,
    "Owner": OWNERS,
}
MANAGED_URLS = ["PRUrl", "Spec"]
# Legacy agent-lifecycle properties we retire (content moves to the page body).
DROP_PROPS = ["WorkLog", "ReviewNotes", "ClaimedBy"]


def _token() -> str:
    tok = os.environ.get("NOTION_TOKEN")
    if not tok:
        sys.exit(
            "NOTION_TOKEN is not set. It should come from the Claude Code environment\n"
            "settings (set once, inherited by every session). If it's missing, ask the\n"
            "user for a session token and export it as NOTION_TOKEN for this session."
        )
    return tok


def _database_id() -> str:
    # Prefer the env var (NOTION_BOARD_ID is the standing name; NOTION_DATABASE_ID
    # is accepted for back-compat). The hardcoded default is only a last resort.
    return (
        os.environ.get("NOTION_BOARD_ID")
        or os.environ.get("NOTION_DATABASE_ID")
        or DEFAULT_DATABASE_ID
    )


def _request(method: str, path: str, body: dict | None = None) -> dict:
    url = f"{API}{path}"
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("Authorization", f"Bearer {_token()}")
    req.add_header("Notion-Version", NOTION_VERSION)
    req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req) as resp:  # noqa: S310 (trusted host)
            return json.loads(resp.read().decode())
    except urllib.error.HTTPError as e:
        sys.exit(
            f"Notion API {e.code} on {method} {path}:\n{e.read().decode(errors='replace')}"
        )
    except urllib.error.URLError as e:
        sys.exit(f"Could not reach Notion: {e}")


def _select(value: str) -> dict:
    return {"select": {"name": value}}


# --- markdown -> Notion blocks (small subset for the ticket-body template) ----


def _rt(text: str) -> list[dict]:
    return [{"type": "text", "text": {"content": text}}] if text else []


def md_to_blocks(text: str) -> list[dict]:
    """Convert the ticket-body template (## headings, - bullets, - [ ] todos,
    plain paragraphs) into Notion block objects. Inline markdown is left literal."""
    blocks: list[dict] = []
    for raw in text.splitlines():
        line = raw.rstrip()
        if not line.strip():
            continue
        if line.startswith("## "):
            blocks.append(
                {"type": "heading_2", "heading_2": {"rich_text": _rt(line[3:])}}
            )
        elif line.startswith("# "):
            blocks.append(
                {"type": "heading_1", "heading_1": {"rich_text": _rt(line[2:])}}
            )
        elif line.lstrip().startswith(("- [ ] ", "- [x] ", "- [X] ")):
            s = line.lstrip()
            checked = s[3].lower() == "x"
            blocks.append(
                {
                    "type": "to_do",
                    "to_do": {"rich_text": _rt(s[6:]), "checked": checked},
                }
            )
        elif line.lstrip().startswith(("- ", "* ")):
            blocks.append(
                {
                    "type": "bulleted_list_item",
                    "bulleted_list_item": {"rich_text": _rt(line.lstrip()[2:])},
                }
            )
        else:
            blocks.append({"type": "paragraph", "paragraph": {"rich_text": _rt(line)}})
    return blocks


# --- commands ----------------------------------------------------------------


def cmd_apply_schema(_args: argparse.Namespace) -> None:
    # Idempotent: only delete legacy props that still exist (Notion 404s on
    # nulling an already-removed property), so re-running is safe.
    existing = set(
        _request("GET", f"/databases/{_database_id()}").get("properties", {})
    )
    props: dict = {}
    for name, options in MANAGED_SELECTS.items():
        props[name] = {"select": {"options": [{"name": o} for o in options]}}
    for name in MANAGED_URLS:
        props[name] = {"url": {}}
    props["ClaimedAt"] = {"date": {}}  # stamped on the Start-work transition
    for name in DROP_PROPS:
        if name in existing:
            props[name] = None  # delete
    _request("PATCH", f"/databases/{_database_id()}", {"properties": props})
    print("Schema applied. Live properties now:")
    cmd_setup_db(_args)
    print(
        "\nNEXT (UI only): add a Unique-ID property named 'ID' with prefix 'TBX'\n"
        "(+ Add property -> ID -> prefix TBX). The API cannot create this type."
    )


def cmd_setup_db(_args: argparse.Namespace) -> None:
    schema = _request("GET", f"/databases/{_database_id()}")
    title = "".join(t.get("plain_text", "") for t in schema.get("title", []))
    print(f"Database: {title}")
    for name, p in schema.get("properties", {}).items():
        t = p["type"]
        extra = ""
        if t in ("select", "status", "multi_select"):
            extra = (
                " -> [" + ", ".join(o["name"] for o in p[t].get("options", [])) + "]"
            )
        print(f"  {name}: {t}{extra}")


def cmd_create(args: argparse.Namespace) -> None:
    props: dict = {"Name": {"title": [{"text": {"content": args.title}}]}}
    props["Status"] = _select(args.status)
    if args.type:
        props["Type"] = _select(args.type)
    if args.priority:
        props["Priority"] = _select(args.priority)
    if args.area:
        props["Area"] = _select(args.area)
    if args.owner:
        props["Owner"] = _select(args.owner)
    if args.pr:
        props["PRUrl"] = {"url": args.pr}
    if args.spec:
        props["Spec"] = {"url": args.spec}
    body = args.body
    if args.body_file:
        with open(args.body_file, encoding="utf-8") as fh:
            body = fh.read()
    payload: dict = {"parent": {"database_id": _database_id()}, "properties": props}
    if body:
        payload["children"] = md_to_blocks(body)
    res = _request("POST", "/pages", payload)
    print(f"Created  {res.get('url', res['id'])}")


def cmd_status(args: argparse.Namespace) -> None:
    _request(
        "PATCH",
        f"/pages/{args.page_id}",
        {"properties": {"Status": _select(args.status)}},
    )
    print(f"{args.page_id} -> {args.status}")


def cmd_link_pr(args: argparse.Namespace) -> None:
    _request(
        "PATCH", f"/pages/{args.page_id}", {"properties": {"PRUrl": {"url": args.url}}}
    )
    print(f"{args.page_id} PRUrl -> {args.url}")


def cmd_list(args: argparse.Namespace) -> None:
    flt: dict = {}
    if args.status:
        flt["filter"] = {"property": "Status", "select": {"equals": args.status}}
    cursor: str | None = None
    while (
        True
    ):  # Notion paginates at 100; loop so `list` never hides older TBX tickets.
        body: dict = {"page_size": 100, **flt}
        if cursor:
            body["start_cursor"] = cursor
        res = _request("POST", f"/databases/{_database_id()}/query", body)
        for page in res.get("results", []):
            props = page.get("properties", {})
            title = "".join(
                t.get("plain_text", "") for t in props.get("Name", {}).get("title", [])
            )
            uid = props.get("ID", {}).get("unique_id") or {}
            ident = (
                f"{uid.get('prefix', '')}-{uid.get('number')}"
                if uid.get("number")
                else page["id"][:8]
            )
            sval = (props.get("Status", {}).get("select") or {}).get("name", "?")
            print(f"  {ident:<8} [{sval:<11}] {title}")
        if not res.get("has_more"):
            break
        cursor = res.get("next_cursor")


def main() -> None:
    p = argparse.ArgumentParser(
        description="Notion board helper for the toolbox taskboard."
    )
    sub = p.add_subparsers(dest="cmd", required=True)

    sub.add_parser("apply-schema").set_defaults(func=cmd_apply_schema)
    sub.add_parser("setup-db").set_defaults(func=cmd_setup_db)

    c = sub.add_parser("create")
    c.add_argument("--title", required=True)
    c.add_argument("--status", default="Backlog", choices=STATUSES)
    c.add_argument("--type", choices=TYPES)
    c.add_argument("--priority", choices=PRIORITIES)
    c.add_argument("--area", choices=AREAS)
    c.add_argument("--owner", choices=OWNERS)
    c.add_argument("--pr")
    c.add_argument("--spec")
    c.add_argument("--body", help="ticket body (markdown subset)")
    c.add_argument("--body-file", help="read the ticket body from a file")
    c.set_defaults(func=cmd_create)

    s = sub.add_parser("status")
    s.add_argument("page_id")
    s.add_argument("status", choices=STATUSES)
    s.set_defaults(func=cmd_status)

    lp = sub.add_parser("link-pr")
    lp.add_argument("page_id")
    lp.add_argument("url")
    lp.set_defaults(func=cmd_link_pr)

    ls = sub.add_parser("list")
    ls.add_argument("--status", choices=STATUSES)
    ls.set_defaults(func=cmd_list)

    args = p.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
