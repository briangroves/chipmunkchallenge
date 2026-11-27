#!/usr/bin/env python3
"""Apply the Board Review app's decisions: approved boards go into the public board feed, every decided board leaves
the private queue.

    tools/.venv/bin/python tools/daily/publish.py [--dry-run]

The feed is boards/approved.json on the game repo's gh-pages branch, served by GitHub Pages at config feed_url. The
game downloads it (and ships a snapshot of it, see snapshot_feed.py). The feed is one flat list of boards,
{"format": 2, "levels": [...]}: each approved board is added on its own, and the game picks it up within the hour.
There are no packs (2026-11-13). Every board goes in drawn in the game's 19 colors, at most 12 per board.

The feed is publish-forever: boards are only ever appended, never removed, changed or reordered, because a board's
place in the level list sets its seed and difficulty in the game. The job checks this before every push.

Boards already in the game come back through Board Review for a second look (slots.py). Approving one changes
nothing; denying one opens its slot, and the next new boards approved take the open slots, in play order, before
any are appended. A feed slot is swapped in the feed right away (same id and place, new name and picture: the only
change to published boards this job makes); a slot in the app's own boards.json waits for snapshot_feed.py.

The feed is pushed first and the queue second, so a failure part way just repeats the same idempotent work next run.
"""
import argparse
import datetime
import glob
import json
import os
import time

import sys

from common import CFG, FEED, QUEUE, TOOLS, ensure_clone, git, load, log, push, save

sys.path.insert(0, TOOLS)
from palette import adapt, limit  # noqa: E402
import slots  # noqa: E402


def boards_of(feed):
    """The feed's boards in order (a feed from before 2026-11-13 grouped them in packs)."""
    if "levels" in feed:
        return feed["levels"]
    return [L for p in feed.get("packs", []) for L in p["levels"]]


def flat(feed):
    return [(L["id"], L["rows"]) for L in boards_of(feed)]


def append(feed, boards):
    """Add boards that aren't in the feed yet, at the end. Returns the ones added."""
    levels = boards_of(feed)
    feed.pop("packs", None)
    feed["format"] = 2
    feed["levels"] = levels
    have = {L["id"] for L in levels}
    added = []
    for b in boards:
        if b["id"] in have:
            continue
        levels.append(dict(id=b["id"], name=b["name"], rows=limit(adapt(b["rows"])), added=b["decided"]))
        have.add(b["id"])
        added.append(b)
    return added


def swap(feed, slot):
    """Put a slot's new board into the feed in place of the denied one: same id and place."""
    for L in boards_of(feed):
        if L["id"] == slot["slot"]:
            b = slot["board"]
            L.update(name=b["name"], rows=limit(adapt(b["rows"])), replaced=slot["filled"], source=b["id"])
            return True
    return False


def publish_feed(approved, swaps, dry_run):
    branch = ensure_clone(FEED, CFG["feed_repo"], CFG["feed_branch"])
    path = os.path.join(FEED, CFG["feed_file"])
    feed = load(path, {"format": 2, "levels": []})
    before = flat(feed)
    swapped = [s for s in swaps if swap(feed, s)]
    added = append(feed, approved)
    if not added and not swapped:
        log("approved boards already in the feed")
        return
    after = flat(feed)
    # Publish-forever: what players have keeps its ids and order; pictures change only in the slots swapped now.
    ok = {s["slot"] for s in swapped}
    if [i for i, _ in after[:len(before)]] != [i for i, _ in before] or any(
            a != b for a, b in zip(after, before) if a[0] not in ok):
        raise RuntimeError("feed would change published boards; refusing to push")
    feed["count"] = len(after)
    feed["updated"] = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    names = ", ".join([f"{s['name']} -> {s['board']['name']}" for s in swapped] + [b["name"] for b in added])
    if dry_run:
        log(f"dry run: would publish: {names}")
        return
    save(path, feed, indent=0)
    what = ([f"swap {len(swapped)}"] if swapped else []) + ([f"add {len(added)}"] if added else [])
    push(FEED, branch, f"Board feed: {' and '.join(what)} ({names})", [CFG["feed_file"]])
    log(f"published {', '.join(what)} ({feed['count']} in feed): {names} [{git(FEED, 'rev-parse', '--short', 'HEAD')}]")


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
    decided = sorted(((dict(by_id[i], decided=d.get("at")), d.get("decision")) for i, (_, d) in decisions.items()
                      if i in by_id), key=lambda x: x[0]["decided"] or "")
    # Boards already in the game: a denial opens its slot (before new approvals, so they can fill it).
    st = slots.state()
    for b, dec in decided:
        if b.get("audit") and dec == "deny":
            slots.deny(st, b, b["decided"])
    # New boards: fill open slots in play order, then append to the feed.
    approved, swaps = [], []
    for b, dec in decided:
        if dec == "approve" and not b.get("audit"):
            s = slots.fill(st, b, b["decided"])
            if s is None:
                approved.append(b)
            elif s["where"] == "feed":
                swaps.append(s)
            else:
                log(f"{b['name']} takes slot #{s['number']} ({s['name']}) in the next App Store build")
    if approved or swaps:
        publish_feed(approved, swaps, a.dry_run)
    if a.dry_run:
        return
    save(slots.SLOTS, st, indent=1)

    with open(os.path.join(QUEUE, "history.jsonl"), "a") as h:
        for i, (f, d) in decisions.items():
            if i in by_id:
                h.write(json.dumps(dict(by_id[i], decision=d.get("decision"), decided=d.get("at"),
                                        reasons=d.get("reasons") or [], note=d.get("note") or "",
                                        excellent=d.get("excellent") or [],
                                        applied=time.strftime("%Y-%m-%dT%H:%M:%S"))) + "\n")
            os.remove(f)
    save(os.path.join(QUEUE, "queue.json"), [b for b in queue if b["id"] not in decisions], indent=0)
    n_ok = sum(d.get("decision") == "approve" for _, d in decisions.values())
    push(QUEUE, "main", f"Applied {len(decisions)} decisions ({n_ok} approved)",
         ["queue.json", "history.jsonl", "decisions", "replace.json"])
    log(f"applied {len(decisions)} decisions ({n_ok} approved, {len(decisions) - n_ok} denied)")


if __name__ == "__main__":
    main()
