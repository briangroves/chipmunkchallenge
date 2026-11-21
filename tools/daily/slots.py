"""Re-review of boards already in the game, and swapping out the ones Brian denies.

    tools/.venv/bin/python tools/daily/slots.py queue       # send every Level Play board in the game to Board Review
    tools/.venv/bin/python tools/daily/slots.py status      # denied slots, which are filled, which still wait

A board can't just be deleted: its place in Level Play sets its seed and challenge, and installed games only take a
feed whose boards keep their ids in order (LevelCatalog.merge). So a denied board's place (its "slot") stays, and
the next new board Brian approves takes it over: same id and place, new name and picture. Slots fill in play order.

Where a slot lives decides when players see the swap:
  - "feed": a board in the public feed (boards/approved.json). publish.py swaps it in the feed straight away.
  - "bundled": a board in the app itself (boards.json "levels" on the release branch). The swap is recorded here
    and written into boards.json by snapshot_feed.py before the next App Store build.

State: replace.json in the queue repo, {"open": [slot...], "filled": [slot + "board": {...}]}.
Re-review items in the queue have ids "audit-<board id>" and an "audit" field; they never count toward the maker's
max_waiting and approving one changes nothing.
"""
import argparse
import json
import os
import sys

from common import CFG, FEED, QUEUE, ROOT, TOOLS, ensure_clone, git, load, log, push, save

sys.path.insert(0, TOOLS)

SLOTS = os.path.join(QUEUE, "replace.json")


def state():
    return load(SLOTS, {"open": [], "filled": []})


def game_boards():
    """Level Play in play order: [(number, where, board)] from the release branch's boards.json and the live feed."""
    branch = CFG.get("release_branch", "version-3.0")
    git(ROOT, "fetch", "-q", "origin", branch)
    nb = json.loads(git(ROOT, "show", f"origin/{branch}:Engine/Sources/ChipmunkEngine/Resources/boards.json"))
    if not nb.get("retire"):
        raise SystemExit("boards.json no longer retires the original boards; slots.py only knows the new layout")
    ensure_clone(FEED, CFG["feed_repo"], CFG["feed_branch"])
    feed = load(os.path.join(FEED, CFG["feed_file"]), {"levels": []})["levels"]
    out = [("bundled", b) for b in nb["levels"]] + [("feed", b) for b in feed]
    return [(n, where, b) for n, (where, b) in enumerate(out, 1)]


def queue_all(again=False):
    from blob_judge import BlobJudge
    from feedback import history
    ensure_clone(QUEUE, CFG["queue_repo"])
    judge = BlobJudge(history())
    seen = set() if again else {h["id"] for h in history() if h.get("audit")}
    qpath = os.path.join(QUEUE, "queue.json")
    queue = load(qpath, [])
    have = {b["id"] for b in queue}
    new = []
    for n, where, b in game_boards():
        qid = f"audit-{b['id']}"
        if qid in have or qid in seen:
            continue
        j = judge.rate(b["rows"])
        new.append(dict(id=qid, name=b["name"], rows=b["rows"], judge=j["stars"],
                        reason=f"Board #{n} in the game now. Deny it to swap in a new board. " + j["reason"],
                        blob_p=j["p"], batch="in the game", audit=dict(slot=b["id"], where=where, number=n)))
    if not new:
        log("every board in the game is already queued or reviewed")
        return
    save(qpath, queue + new, indent=0)
    push(QUEUE, "main", f"Re-review {len(new)} boards already in the game", ["queue.json"])
    log(f"queued {len(new)} boards from the game for review ({len(queue) + len(new)} in the queue)")


def deny(st, b, decided):
    """A re-reviewed board was denied: its slot opens for the next approved board."""
    a = b["audit"]
    if any(s["slot"] == a["slot"] for s in st["open"] + st["filled"]):
        return
    st["open"].append(dict(a, name=b["name"], denied=decided))
    st["open"].sort(key=lambda s: s["number"])


def fill(st, board, decided):
    """Give the earliest open slot to a newly approved board. Returns the slot, or None if none is open."""
    if not st["open"]:
        return None
    s = st["open"].pop(0)
    s = dict(s, board=dict(id=board["id"], name=board["name"], rows=board["rows"]), filled=decided)
    st["filled"].append(s)
    return s


def status():
    ensure_clone(QUEUE, CFG["queue_repo"])
    st = state()
    queued = sum(1 for b in load(os.path.join(QUEUE, "queue.json"), []) if b.get("audit"))
    print(f"{queued} game boards waiting for re-review")
    print(f"{len(st['open'])} denied, waiting for a new board:")
    for s in st["open"]:
        print(f"  #{s['number']:3d} {s['name']} ({s['where']})")
    print(f"{len(st['filled'])} swapped:")
    for s in st["filled"]:
        print(f"  #{s['number']:3d} {s['name']} -> {s['board']['name']} ({s['where']}"
              f"{', in the next App Store build' if s['where'] == 'bundled' else ', live in the feed'})")


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("what", choices=["queue", "status"])
    ap.add_argument("--again", action="store_true", help="queue boards even if already re-reviewed")
    a = ap.parse_args()
    queue_all(a.again) if a.what == "queue" else status()
