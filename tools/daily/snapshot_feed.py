#!/usr/bin/env python3
"""Get the game's boards ready for a release build (run it before every App Store build, from the release checkout).

    python3 tools/daily/snapshot_feed.py

1. Copies the live feed (config feed_url) into Engine/Sources/ChipmunkEngine/Resources/approved-boards.json, so a
   fresh install has every board published so far, offline. The app then downloads only boards past this count.
   Feed boards Brian denied on a second look are already swapped in the feed (publish.py), so they come along.
2. Swaps the boards in the app's own boards.json "levels" that Brian denied on a second look for the new boards that
   took their slots (slots.py, replace.json in the queue repo): same id and place, new name and picture.
3. Writes the denied boards still waiting for a new board into boards.json "skip" (id + fingerprint of the denied
   picture): the game passes over them but keeps every board's index, so seeds and the feed's order don't change.
   When a new board later fills the slot (same id, new rows), the fingerprint stops matching and it plays again.
"""
import json
import os
import sys
import urllib.request

from common import CFG, QUEUE, ROOT, TOOLS, ensure_clone, load, log, save

sys.path.insert(0, TOOLS)
RES = os.path.join(ROOT, "Engine/Sources/ChipmunkEngine/Resources")
OUT = os.path.join(RES, "approved-boards.json")
BUNDLED = os.path.join(RES, "boards.json")


def snapshot_feed():
    with urllib.request.urlopen(CFG["feed_url"], timeout=30) as r:
        feed = json.load(r)
    count = lambda f: len(f["levels"]) if "levels" in f else sum(len(p["levels"]) for p in f.get("packs", []))
    old = json.load(open(OUT)) if os.path.exists(OUT) else {"levels": []}
    n_old, n_new = count(old), count(feed)
    if n_new < n_old:
        raise SystemExit(f"feed has {n_new} boards but the game already ships {n_old}; not shrinking it")
    swapped = sum(1 for a, b in zip(old["levels"], feed["levels"]) if a["id"] == b["id"] and a["rows"] != b["rows"])
    save(OUT, feed, indent=0)
    log(f"snapshot: {n_new} boards ({n_new - n_old} new, {swapped} swapped) -> {os.path.relpath(OUT, ROOT)}")


def fingerprint(rows):
    """FNV-1a 64-bit hex of the rows joined by newlines (LevelCatalog.fingerprint in the engine)."""
    h = 0xCBF29CE484222325
    for b in "\n".join(rows).encode():
        h = ((h ^ b) * 0x100000001B3) & 0xFFFFFFFFFFFFFFFF
    return f"{h:016x}"


def swap_bundled():
    from palette import adapt, limit
    ensure_clone(QUEUE, CFG["queue_repo"])
    st = load(os.path.join(QUEUE, "replace.json"), {"open": [], "filled": []})
    nb = json.load(open(BUNDLED))
    by_id = {L["id"]: L for L in nb["levels"]}
    feed_by_id = {L["id"]: L for L in json.load(open(OUT))["levels"]}
    n = 0
    for s in st["filled"]:
        L = by_id.get(s["slot"])
        if s["where"] != "bundled" or L is None or L.get("source") == s["board"]["id"]:
            continue
        log(f"  #{s['number']} {L['name']} -> {s['board']['name']}")
        L.update(name=s["board"]["name"], rows=limit(adapt(s["board"]["rows"])), source=s["board"]["id"])
        n += 1
    skip = []
    for s in st["open"]:
        L = (feed_by_id if s["where"] == "feed" else by_id).get(s["slot"])
        if L is None:
            log(f"  denied board not found: #{s['number']} {s['name']} ({s['where']})")
            continue
        skip.append({"id": L["id"], "fingerprint": fingerprint(L["rows"])})
        log(f"  skipped until a new board fills it: #{s['number']} {s['name']} ({s['where']})")
    if n or nb.get("skip", []) != skip:
        nb["skip"] = skip
        with open(BUNDLED, "w") as f:
            json.dump(nb, f, separators=(",", ":"))
            f.write("\n")
    log(f"boards.json: {n} board{'s' * (n != 1)} swapped, {len(skip)} skipped")


def main():
    snapshot_feed()
    swap_bundled()


if __name__ == "__main__":
    main()
