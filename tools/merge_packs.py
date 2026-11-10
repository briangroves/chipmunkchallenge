#!/usr/bin/env python3
"""Merge boards built by parallel pack builders into the game's board file.

    python3 tools/merge_packs.py /path/worker-0.json /path/worker-1.json ...

Packs from the worker files that the game's file doesn't have yet are added; every pack is put in queue order and
every new level renumbered (ids are "<subject>-<level>"), with the blind-check results in tools/packs/checks/ renamed
to match. Workers use separate backdrop lanes (make_pack.py --lane), so no background repeats.
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import make_pack as mp  # noqa: E402


# Packs that came out too small to stand alone, folded into a related pack (boards appended at its end), and the
# merged pack's new name where it changes.
FOLD = {"robots": "tech", "fair": "party", "picnic": "fruit", "dinos": "monsters", "cats": "cute",
        "dogs": "pets2", "story2": "baby", "farm2": "spring", "bakery": "drinks", "treats2": "sweets",
        "workshop": "home", "world": "buildings", "vehicles2": "transport3", "breakfast": "meals",
        "seasons": "garden", "magic": "fantasy", "food4": "fruitfaces"}
RENAME = {"monsters": "Monsters & Dinos", "cute": "Cute Critters & Cats", "transport3": "On the Move",
          "garden": "Garden Seasons", "home": "Home & Workshop", "buildings": "Around the World"}


def fold(data):
    packs = {p["id"]: p for p in data["packs"]}
    for small, big in FOLD.items():
        if small in packs and big in packs:
            packs[big]["levels"] += packs[small]["levels"]
            packs[big].setdefault("merged", []).append(small)
            data["packs"].remove(packs[small])
            # The small pack's blind-check results move with its boards.
            src = os.path.join(HERE, "packs", "checks", small + ".json")
            dst = os.path.join(HERE, "packs", "checks", big + ".json")
            if os.path.exists(src):
                both = json.load(open(dst)) if os.path.exists(dst) else {}
                both.update(json.load(open(src)))
                json.dump(both, open(dst, "w"), indent=1)
                os.remove(src)
    for pid, name in RENAME.items():
        if pid in packs:
            packs[pid]["name"] = name


def main():
    data = json.load(open(mp.BOARDS))
    have = {p["id"] for p in data["packs"]}
    for path in sys.argv[1:]:
        for p in json.load(open(path))["packs"]:
            if p["id"] not in have:
                data["packs"].append(p)
                have.add(p["id"])
    fold(data)
    order = ["farm"] + [p["id"] for p in json.load(open(os.path.join(HERE, "packs", "queue.json")))["packs"]]
    data["packs"].sort(key=lambda p: order.index(p["id"]) if p["id"] in order else len(order))
    n = mp.FIRST_NEW
    for p in data["packs"]:
        cpath = os.path.join(HERE, "packs", "checks", p["id"] + ".json")
        checks = json.load(open(cpath)) if os.path.exists(cpath) else {}
        renamed = {}
        for L in p["levels"]:
            new = f"{L['name'].lower().replace(' ', '-')}-{n + 1}"
            if L["id"] in checks:
                renamed[new] = checks[L["id"]]
            L["id"] = new
            n += 1
        if checks:
            json.dump(renamed, open(cpath, "w"), indent=1)
    json.dump(data, open(mp.BOARDS, "w"), separators=(",", ":"))
    print(f"{len(data['packs'])} packs, {n} levels")


if __name__ == "__main__":
    main()
