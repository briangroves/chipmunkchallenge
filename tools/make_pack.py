#!/usr/bin/env python3
"""Build a pack of new boards from free clipart.

    python3 -I tools/make_pack.py tools/packs/farm.json
    python3 -I tools/make_pack.py tools/packs/queue.json --next 2     # the next 2 packs from the queue not yet built
    python3 -I tools/make_pack.py tools/packs/queue.json --pack woodland

The pack file lists the subjects and a search phrase for each:
    {"id": "farm", "name": "Farm Animals", "subjects": [{"name": "Cow", "query": "cow cartoon"}, ...]}

For each subject: search Openverse for CC0 (public domain) clipart, download a few candidates, convert each with
image_to_board, keep the best, and put it on its board's backdrop (a theme no other board shares exactly). The pack is
written into Engine/Sources/ChipmunkEngine/Resources/boards.json (replacing a pack with the same id), each board with
its source and license, and a review sheet of the whole pack is saved next to the pack file.

Downloads are kept in ~/Library/Caches/chipmunk-boards so a rerun doesn't fetch them again.
"""
import json
import os
import subprocess
import sys
import time
import urllib.parse
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import image_to_board as conv  # noqa: E402

ROOT = os.path.dirname(HERE)
BOARDS = os.path.join(ROOT, "Engine/Sources/ChipmunkEngine/Resources/boards.json")
CACHE = os.path.expanduser("~/Library/Caches/chipmunk-boards")
FIRST_NEW = 170          # board index of the first new board (the 170 original boards come first)
UA = {"User-Agent": "chipmunk-board-import/0.1"}
# Titles that are rarely a single clean subject at board size.
SKIP = ("vintage", "collage", "pattern", "seamless", "set", "frame", "line art", "drawing", "sketch", "silhouette",
        "engraving", "illustration of", "map", "logo", "icons", "badge", "border",
        # food, toys and diagrams of the animal rather than the animal
        "roast", "cook", "meat", "cuts", "chart", "recipe", "dish", "rubber", "toy", "skull", "skeleton")


def search(query, n=20):
    url = "https://api.openverse.org/v1/images/?" + urllib.parse.urlencode(
        {"q": query, "license": "cc0", "page_size": n})
    for attempt in range(4):
        try:
            with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=30) as r:
                return json.load(r).get("results", [])
        except Exception:
            time.sleep(5 * (attempt + 1))
    return []


def fetch(item):
    os.makedirs(CACHE, exist_ok=True)
    path = os.path.join(CACHE, item["id"] + ".img")
    if not os.path.exists(path):
        with urllib.request.urlopen(urllib.request.Request(item["url"], headers=UA), timeout=60) as r:
            open(path, "wb").write(r.read())
    return path


def score(info):
    """Higher is better: flat art (little black ink), a solid shape, a good size, a handful of colors."""
    s = 0.0
    s -= 2.0 * max(0.0, info["ink"] - 0.08)
    s -= 1.5 * abs(info["fill"] - 0.6)
    s += min(1.0, info["size"] / 450)
    ncol = len([k for k, v in info["colors"].items() if v >= 6])
    s -= 0.15 * max(0, ncol - 6) + 0.3 * max(0, 3 - ncol)
    return s


def signature(cells):
    """The subject's shape and colors, to spot the same picture listed twice under different ids."""
    return {f"{r},{c},{k}" for (r, c), k in cells.items()}


def similar(a, b):
    return len(a & b) / max(1, len(a | b)) > 0.6


def best_board(subject, board_no, pick, taken, taken_sigs=(), max_candidates=6):
    results = search(subject["query"])
    # The title has to name the subject (any of `match`, by default the subject's name), so a search for "goose"
    # can't hand back a snail.
    match = [m.lower() for m in subject.get("match", [subject["name"].split()[-1]])]
    avoid = [a.lower() for a in subject.get("avoid", [])]
    picks = [r for r in results
             if r["id"] not in taken and not any(w in r["title"].lower() for w in SKIP + tuple(avoid))
             and any(m in r["title"].lower() for m in match)]
    picks.sort(key=lambda r: r.get("source") != "rawpixel")
    best = None
    for item in picks[:max_candidates]:
        try:
            path = fetch(item)
            cells, info = conv.make_subject(path)
        except Exception as e:  # noqa: BLE001 - a bad download or a rejected image just drops that candidate
            print(f"   skip {item['title'][:50]}: {e}")
            continue
        sig = signature(cells)
        if any(similar(sig, t) for t in taken_sigs):
            print(f"   skip {item['title'][:50]}: same picture as another board")
            continue
        s = score(info)
        print(f"   {s:+.2f} {item['title'][:60]}")
        if best is None or s > best[0]:
            best = (s, cells, info, item, sig)
    if not best:
        return None
    _, cells, info, item, sig = best
    import backdrops
    main = max(info["colors"], key=info["colors"].get)
    rows, theme, variant = conv.compose(cells, info, pick(dark_subject=main in ("K", "U", "E", "N", "M", "V")))
    return {
        "id": f"{subject['name'].lower().replace(' ', '-')}-{board_no + 1}",
        "name": subject["name"],
        "rows": rows,
        "theme": backdrops.THEMES[theme]["name"],
        "variant": variant,
        "sig": sorted(sig),
        "source": {k: item.get(k) for k in ("id", "title", "foreign_landing_url", "url", "license", "license_version",
                                             "source", "creator")},
    }


def sheet(levels, out):
    """All boards of the pack in one picture, five across, for review."""
    Z, cols = 6, 5
    rows_n = (len(levels) + cols - 1) // cols
    W, H = cols * (40 * Z + 6), rows_n * (40 * Z + 6)
    img = bytearray(bytes((30, 30, 30)) * (W * H))
    for i, L in enumerate(levels):
        oy, ox = (i // cols) * (40 * Z + 6), (i % cols) * (40 * Z + 6)
        for r, row in enumerate(L["rows"]):
            for c, ch in enumerate(row):
                p = bytes(conv.RGB[ch])
                for y in range(Z):
                    base = ((oy + r * Z + y) * W + ox + c * Z) * 3
                    img[base:base + 3 * Z] = p * Z
    with open(out + ".ppm", "wb") as f:
        f.write(f"P6 {W} {H} 255\n".encode())
        f.write(img)
    subprocess.run(["sips", "-s", "format", "png", out + ".ppm", "--out", out], capture_output=True)
    os.remove(out + ".ppm")


def normalize(spec):
    """Subjects may be plain names: the search phrase and title match then come from the name."""
    subs = []
    for s in spec["subjects"]:
        if isinstance(s, str):
            s = {"name": s}
        s.setdefault("query", f"{s['name'].lower()} cartoon clipart")
        subs.append(s)
    return dict(spec, subjects=subs)


def main():
    import argparse
    ap = argparse.ArgumentParser()
    ap.add_argument("file")
    ap.add_argument("--pack", help="build this pack from a queue file")
    ap.add_argument("--next", type=int, help="build the next N packs from a queue file that aren't built yet")
    a = ap.parse_args()
    doc = json.load(open(a.file))
    if "packs" not in doc:
        build(normalize(doc), a.file)
        return
    built = {p["id"] for p in json.load(open(BOARDS))["packs"]} if os.path.exists(BOARDS) else set()
    todo = [p for p in doc["packs"] if (a.pack and p["id"] == a.pack) or (a.next and p["id"] not in built)]
    for spec in todo[: a.next or len(todo)]:
        build(normalize(spec), os.path.join(os.path.dirname(a.file), spec["id"] + ".json"))


def build(spec, sheet_base):
    data = json.load(open(BOARDS)) if os.path.exists(BOARDS) else {"format": 1, "packs": []}
    others = [p for p in data["packs"] if p["id"] != spec["id"]]
    start = FIRST_NEW + sum(len(p["levels"]) for p in others)
    import backdrops
    names = [t["name"] for t in backdrops.THEMES]
    used, recent = {}, []
    for p in others:
        for L in p["levels"]:
            i = names.index(L["theme"])
            used[i] = max(used.get(i, 0), L.get("variant", 0) + 1)
            recent = (recent + [i])[-12:]
    groups = spec.get("themes", ["land"])
    levels = []
    for k, subject in enumerate(spec["subjects"]):
        n = start + k
        print(f"Level {n + 1}: {subject['name']}")
        taken = {L["source"]["id"] for p in others for L in p["levels"] if L["source"].get("id")} | \
                {L["source"]["id"] for L in levels}
        sigfile = os.path.join(CACHE, "signatures.json")
        allsig = json.load(open(sigfile)) if os.path.exists(sigfile) else {}
        sigs = [set(allsig.get(L["id"], [])) for p in others for L in p["levels"]] + [set(L["sig"]) for L in levels]
        board = best_board(subject, n, lambda **kw: backdrops.pick_themes(groups, used, recent, **kw), taken, sigs)
        if board:
            levels.append(board)
            i = names.index(board["theme"])
            used[i] = board["variant"] + 1
            recent = (recent + [i])[-12:]
            print(f"   -> {board['theme']} #{board['variant'] + 1}")
        else:
            print("   -> no usable image")
    data["packs"] = others + [{"id": spec["id"], "name": spec["name"], "levels": levels}]
    sigfile = os.path.join(CACHE, "signatures.json")
    allsig = json.load(open(sigfile)) if os.path.exists(sigfile) else {}
    for L in levels:
        allsig[L["id"]] = L.pop("sig")
    json.dump(allsig, open(sigfile, "w"))
    json.dump(data, open(BOARDS, "w"), separators=(",", ":"))
    out = os.path.splitext(sheet_base)[0] + "-sheet.png"
    sheet(levels, out)
    print(f"Wrote {len(levels)} boards to {BOARDS}; review sheet {out}")


if __name__ == "__main__":
    main()
