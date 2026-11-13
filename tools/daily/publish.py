#!/usr/bin/env python3
"""Apply the Board Review app's decisions: approved boards go into the public board feed, every decided board leaves
the private queue.

    tools/.venv/bin/python tools/daily/publish.py [--dry-run]

The feed is boards/approved.json on the game repo's gh-pages branch, served by GitHub Pages at config feed_url. The
game downloads it (and ships a snapshot of it, see snapshot_feed.py). Boards are grouped in packs of `pack_size`
named "<pack_name> N".

The feed is publish-forever: boards are only ever appended, never removed, changed or reordered, because a board's
place in the level list sets its seed and difficulty in the game. The job checks this before every push.

The feed is pushed first and the queue second, so a failure part way just repeats the same idempotent work next run.
"""
import argparse
import datetime
import glob
import json
import os
import time

from common import CFG, FEED, QUEUE, ensure_clone, git, load, log, push, save


def flat(feed):
    return [(L["id"], L["rows"]) for p in feed.get("packs", []) for L in p["levels"]]


def append(feed, boards):
    """Add boards that aren't in the feed yet, at the end. Returns the ones added."""
    packs = feed.setdefault("packs", [])
    have = {L["id"] for p in packs for L in p["levels"]}
    added = []
    for b in boards:
        if b["id"] in have:
            continue
        if not packs or len(packs[-1]["levels"]) >= CFG["pack_size"]:
            n = len(packs) + 1
            packs.append(dict(id=f"{CFG['pack_id']}{n}", name=f"{CFG['pack_name']} {n}", levels=[]))
        packs[-1]["levels"].append(dict(id=b["id"], name=b["name"], rows=b["rows"], added=b["decided"]))
        have.add(b["id"])
        added.append(b)
    return added


def publish_feed(approved, dry_run):
    branch = ensure_clone(FEED, CFG["feed_repo"], CFG["feed_branch"])
    path = os.path.join(FEED, CFG["feed_file"])
    feed = load(path, {"format": 1, "packs": []})
    before = flat(feed)
    added = append(feed, approved)
    if not added:
        log("approved boards already in the feed")
        return
    after = flat(feed)
    if after[:len(before)] != before:  # publish-forever: what players have must never move or change
        raise RuntimeError("feed would change published boards; refusing to push")
    feed["count"] = len(after)
    feed["updated"] = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    names = ", ".join(b["name"] for b in added)
    if dry_run:
        log(f"dry run: would publish {len(added)}: {names}")
        return
    save(path, feed, indent=0)
    push(FEED, branch, f"Board feed: add {len(added)} approved board{'s' * (len(added) != 1)} ({names})",
         [CFG["feed_file"]])
    log(f"published {len(added)} ({feed['count']} in feed): {names} [{git(FEED, 'rev-parse', '--short', 'HEAD')}]")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args()

    ensure_clone(QUEUE, CFG["queue_repo"])
    queue = load(os.path.join(QUEUE, "queue.json"), [])
    by_id = {b["id"]: b for b in queue}
    decisions = {}
    for f in glob.glob(os.path.join(QUEUE, "decisions", "*.json")):
        try:
            d = json.load(open(f))
            decisions[d["id"]] = (f, d)
        except Exception as e:  # noqa: BLE001
            log("bad decision file", f, e)
    if not decisions:
        log("no decisions to apply")
        return

    # In the order Brian decided them, so the feed reads in review order.
    approved = sorted((dict(by_id[i], decided=d.get("at")) for i, (_, d) in decisions.items()
                       if i in by_id and d.get("decision") == "approve"), key=lambda b: b["decided"] or "")
    if approved:
        publish_feed(approved, a.dry_run)
    if a.dry_run:
        return

    with open(os.path.join(QUEUE, "history.jsonl"), "a") as h:
        for i, (f, d) in decisions.items():
            if i in by_id:
                h.write(json.dumps(dict(by_id[i], decision=d.get("decision"), decided=d.get("at"),
                                        applied=time.strftime("%Y-%m-%dT%H:%M:%S"))) + "\n")
            os.remove(f)
    save(os.path.join(QUEUE, "queue.json"), [b for b in queue if b["id"] not in decisions], indent=0)
    n_ok = sum(d.get("decision") == "approve" for _, d in decisions.values())
    push(QUEUE, "main", f"Applied {len(decisions)} decisions ({n_ok} approved)",
         ["queue.json", "history.jsonl", "decisions"])
    log(f"applied {len(decisions)} decisions ({n_ok} approved, {len(decisions) - n_ok} denied)")


if __name__ == "__main__":
    main()
