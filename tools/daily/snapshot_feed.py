#!/usr/bin/env python3
"""Copy the public board feed into the game as its built-in starting set (run before a release build).

    python3 tools/daily/snapshot_feed.py

Writes Engine/Sources/ChipmunkEngine/Resources/approved-boards.json from the live feed (config feed_url), so a fresh
install has every board published so far, offline. The app can then download only boards past this count.
"""
import json
import os
import urllib.request

from common import CFG, ROOT, log, save

OUT = os.path.join(ROOT, "Engine/Sources/ChipmunkEngine/Resources/approved-boards.json")


def main():
    with urllib.request.urlopen(CFG["feed_url"], timeout=30) as r:
        feed = json.load(r)
    count = lambda f: len(f["levels"]) if "levels" in f else sum(len(p["levels"]) for p in f.get("packs", []))
    old = json.load(open(OUT)) if os.path.exists(OUT) else {"levels": []}
    n_old, n_new = count(old), count(feed)
    if n_new < n_old:
        raise SystemExit(f"feed has {n_new} boards but the game already ships {n_old}; not shrinking it")
    save(OUT, feed, indent=0)
    log(f"snapshot: {n_new} boards ({n_new - n_old} new) -> {os.path.relpath(OUT, ROOT)}")


if __name__ == "__main__":
    main()
