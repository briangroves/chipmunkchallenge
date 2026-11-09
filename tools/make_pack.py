#!/usr/bin/env python3
"""Build a pack of new boards from free clipart.

    python3 tools/make_pack.py tools/packs/farm.json
    python3 tools/make_pack.py tools/packs/queue.json --next 2     # the next 2 packs from the queue not yet built
    python3 tools/make_pack.py tools/packs/queue.json --pack woodland
    python3 tools/make_pack.py tools/packs/queue.json --pack woodland --no-check   # without the blind check

The pack file lists the subjects and a search phrase for each:
    {"id": "farm", "name": "Farm Animals", "subjects": [{"name": "Cow", "query": "cow cartoon"}, ...]}

For each subject: search Openverse for CC0 (public domain) clipart, download a few candidates, convert each with
image_to_board, put the best few on the board's backdrop and show each to Claude without saying what it is (the blind
check in check_boards.py); keep the one it recognises best. A subject with no passing board gives way to the pack's
"spares" until the pack has 20 that pass. Each board goes on a backdrop (a theme no other board shares exactly). The pack is
written into Engine/Sources/ChipmunkEngine/Resources/boards.json (replacing a pack with the same id), each board with
its source and license, and a review sheet of the whole pack is saved next to the pack file.

Downloads are kept in ~/Library/Caches/chipmunk-boards so a rerun doesn't fetch them again.
"""
import json
import os
import re
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
        "roast", "cook", "meat", "thanksgiving", "dinner", "platter", "plate", "baked", "cuts", "chart", "recipe", "dish", "rubber", "toy", "skull", "skeleton",
        # pictures in a frame or circle, and realistic art, read badly at 40x40 (the blind check's worst boards)
        "circle", "round", "emblem", "icon", "stamp", "label", "realistic", "photo", "watercolor", "painting",
        "ornament", "wreath", "pattern", "mandala")


def search(query, n=20):
    """Openverse results for a query (titles always text), cached so a rebuild doesn't search again."""
    key = os.path.join(CACHE, "search", urllib.parse.quote(query, safe="") + ".json")
    if os.path.exists(key):
        return json.load(open(key))
    found = _search(query, n)
    for r in found:
        r["title"] = r.get("title") or ""
    if found:
        os.makedirs(os.path.dirname(key), exist_ok=True)
        json.dump(found, open(key, "w"))
    return found


def _search(query, n=20):
    url = "https://api.openverse.org/v1/images/?" + urllib.parse.urlencode(
        {"q": query, "license": "cc0", "page_size": n})
    # Openverse's anonymous limit is low: space searches out and back off on errors (a 429 used to leave subjects
    # with no picture).
    time.sleep(4)
    for attempt in range(7):
        try:
            with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=30) as r:
                return json.load(r).get("results", [])
        except Exception:
            time.sleep(15 * (attempt + 1))
    print("   search failed:", query)
    return []


def fetch(item):
    os.makedirs(CACHE, exist_ok=True)
    path = os.path.join(CACHE, item["id"] + ".img")
    if not os.path.exists(path):
        with urllib.request.urlopen(urllib.request.Request(item["url"], headers=UA), timeout=60) as r:
            open(path, "wb").write(r.read())
    return path


TOUCHUPS = os.path.join(HERE, "packs", "touchups")


def touch_up(board):
    """Hand fixes for a board, kept in tools/packs/touchups/<board id>.json so they survive rebuilds:
    {"layers": [{"at": [row, col], "rows": ["..KW..", ...]}, ...]} where "." keeps the block underneath."""
    path = os.path.join(TOUCHUPS, board["id"] + ".json")
    if not os.path.exists(path):
        return board
    g = [list(r) for r in board["rows"]]
    for layer in json.load(open(path))["layers"]:
        r0, c0 = layer["at"]
        for i, row in enumerate(layer["rows"]):
            for j, ch in enumerate(row):
                if ch != "." and 0 <= r0 + i < 40 and 0 <= c0 + j < 40:
                    g[r0 + i][c0 + j] = ch
    board["rows"] = ["".join(r) for r in g]
    board["touched"] = True
    return board


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


def candidates(subject, taken, taken_sigs=(), max_candidates=8):
    """Convert the best few search results for a subject, best heuristic score first."""
    # The first phrasings that return enough pictures naming the subject win; long phrasings often return nothing.
    name = subject["name"].lower()
    match = [m.lower() for m in subject.get("match", [subject["name"].split()[-1]])]
    queries = [subject["query"]]
    for q in (f"cute {name} cartoon", f"{name} cartoon", f"{name} clipart", f"{name} illustration",
              f"{name} png sticker", f"{name} vector"):
        if q not in queries:
            queries.append(q)
    results = []
    for q in queries:
        found = search(q)
        results += [r for r in found if r["id"] not in {x["id"] for x in results}]
        if len([r for r in results if any(m in r["title"].lower() for m in match)]) >= max_candidates:
            break
    # The title has to name the subject (any of `match`, by default the subject's name), so a search for "goose"
    # can't hand back a snail. Skip words that are part of the subject's own name don't count ("Snow Globe").
    skip = tuple(w for w in SKIP if w not in name) + tuple(a.lower() for a in subject.get("avoid", []))
    # Dated prints and scientific plates ("Musk Ox (Ovibos moschatus)", "Snowy Owl (1832–1837)") are realistic
    # engravings that turn into noise at 40x40.
    old = re.compile(r"\b1[5-9]\d\d\b|\(c(a)?\.|viviparous|abbildungen|\([A-Z][a-z]+ [a-z]+\)")
    # Museum scans (etchings, dissections, coats of arms) come up for rarer animals; only pictures whose title says
    # they are clipart, cartoons or stickers convert well.
    style = ("clipart", "clip art", "cartoon", "sticker", "png", "vector", "image element", "illustration")
    picks = [r for r in results
             if r["id"] not in taken and not any(w in r["title"].lower() for w in skip) and not old.search(r["title"])
             and any(w in r["title"].lower() for w in style)
             and not any(w in r["title"].lower() for w in ("etching", "dissection", "coloured", "lithograph"))
             and any(m in r["title"].lower() for m in match)]
    picks.sort(key=lambda r: r.get("source") != "rawpixel")
    out = []
    for item in picks[:max_candidates + 2]:
        if len(out) >= max_candidates:
            break
        try:
            path = fetch(item)
            cells, info = conv.make_subject(path)
        except Exception as e:  # noqa: BLE001 - a bad download or a rejected image just drops that candidate
            print(f"   skip {item['title'][:50]}: {e}")
            continue
        sig = signature(cells)
        if any(similar(sig, t) for t in taken_sigs) or any(similar(sig, o[4]) for o in out):
            print(f"   skip {item['title'][:50]}: same picture as another board")
            continue
        out.append((score(info), cells, info, item, sig))
    out.sort(key=lambda o: -o[0])
    return out


def best_board(subject, pick, taken, taken_sigs=(), client=None, tries=6):
    """The subject's board: its candidates composed onto a backdrop and, with a client, each shown blind to Claude;
    the one it recognises best wins (else the best heuristic score). None if nothing usable was found."""
    import backdrops
    found = candidates(subject, taken, taken_sigs)
    if not found:
        return None
    boards = []
    for s, cells, info, item, sig in found[: tries if client else 1]:
        main = max(info["colors"], key=info["colors"].get)
        rows, theme, variant = conv.compose(cells, info, pick(dark_subject=main in ("K", "U", "E", "N", "M", "V")))
        boards.append({
            "name": subject["name"],
            "rows": rows,
            "theme": backdrops.THEMES[theme]["name"],
            "variant": variant,
            "sig": sorted(sig),
            "source": {k: item.get(k) for k in ("id", "title", "foreign_landing_url", "url", "license",
                                                 "license_version", "source", "creator")},
            "_heuristic": s,
        })
    if client:
        from concurrent.futures import ThreadPoolExecutor
        with ThreadPoolExecutor(len(boards)) as ex:
            checks = list(ex.map(lambda B: blind(client, subject["name"], B["rows"]), boards))
        for B, c in zip(boards, checks):
            B["check"] = c
            print(f"   {c.get('score', '-'):>3} {c.get('grade') or 'error':4} {c.get('guess', c.get('error', ''))[:40]!r:<42}"
                  f" <- {B['source']['title'][:40]}")
        boards.sort(key=lambda B: (-(B["check"].get("score") or -1), -B["_heuristic"]))
    best = boards[0]
    best.pop("_heuristic")
    return best


def blind(client, name, rows):
    """Show the board to Claude without saying what it is (tools/check_boards.py) and grade the answer."""
    import hashlib
    import tempfile
    import check_boards as cb
    digest = hashlib.sha256("".join(rows).encode()).hexdigest()[:16]
    # Answers are cached by picture, so a rebuild only asks about boards that changed.
    cache = os.path.join(CACHE, "blind", f"{digest}-{name.lower().replace(' ', '-')}.json")
    if os.path.exists(cache):
        return json.load(open(cache))
    with tempfile.TemporaryDirectory() as d:
        png = os.path.join(d, "board.png")
        cb.render_png(rows, png)
        for attempt in range(3):
            try:
                ans = cb.ask(client, png)
                res = dict(ans, digest=digest, grade=cb.grade(name, ans), score=cb.score(name, ans))
                os.makedirs(os.path.dirname(cache), exist_ok=True)
                json.dump(res, open(cache, "w"))
                return res
            except Exception as e:  # noqa: BLE001 - retry, then give up on this candidate's check
                err = str(e)
                time.sleep(5 * (attempt + 1))
    return {"digest": digest, "grade": None, "error": err[:200]}


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
    def one(s):
        s = {"name": s} if isinstance(s, str) else dict(s)
        s.setdefault("query", f"{s['name'].lower()} cartoon clipart")
        return s
    return dict(spec, subjects=[one(s) for s in spec["subjects"]], spares=[one(s) for s in spec.get("spares", [])])


def main():
    import argparse
    ap = argparse.ArgumentParser()
    ap.add_argument("file")
    ap.add_argument("--pack", help="build this pack from a queue file")
    ap.add_argument("--next", type=int, help="build the next N packs from a queue file that aren't built yet")
    ap.add_argument("--until", type=int, help="build queued packs not built yet until the game has this many levels")
    ap.add_argument("--no-check", action="store_true", help="skip the blind check (no API calls)")
    a = ap.parse_args()
    client = None
    if not a.no_check:
        import anthropic
        client = anthropic.Anthropic()
    doc = json.load(open(a.file))
    if "packs" not in doc:
        build(normalize(doc), a.file, client)
        return
    built = {p["id"] for p in json.load(open(BOARDS))["packs"]} if os.path.exists(BOARDS) else set()
    if a.until:
        # Build packs in queue order until the game reaches the target (170 original levels + the new boards).
        for spec in [p for p in doc["packs"] if p["id"] not in built]:
            have = FIRST_NEW + sum(len(p["levels"]) for p in json.load(open(BOARDS))["packs"])
            if have >= a.until:
                break
            print(f"=== {spec['name']} ({have} levels so far, target {a.until})")
            build(normalize(spec), os.path.join(os.path.dirname(a.file), spec["id"] + ".json"), client)
        have = FIRST_NEW + sum(len(p["levels"]) for p in json.load(open(BOARDS))["packs"])
        print(f"{have} levels" + ("" if have >= a.until else f": the queue ran out {a.until - have} short"))
        return
    todo = [p for p in doc["packs"] if (a.pack and p["id"] == a.pack) or (a.next and p["id"] not in built)]
    for spec in todo[: a.next or len(todo)]:
        build(normalize(spec), os.path.join(os.path.dirname(a.file), spec["id"] + ".json"), client)


PACK_SIZE = 20


def build(spec, sheet_base, client=None):
    """Build the pack's boards. With a client, each subject's board must pass the blind check; subjects that don't are
    replaced by the pack's spares until it has PACK_SIZE passing boards (then the best weak ones fill any gap)."""
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
    sigfile = os.path.join(CACHE, "signatures.json")
    allsig = json.load(open(sigfile)) if os.path.exists(sigfile) else {}
    taken = {L["source"]["id"] for p in others for L in p["levels"] if L["source"].get("id")}
    others_sigs = [set(allsig.get(L["id"], [])) for p in others for L in p["levels"]]
    made = []
    good = lambda B: not client or B["check"].get("grade") == "pass"
    for k, subject in enumerate(spec["subjects"] + spec.get("spares", [])):
        spare = k >= len(spec["subjects"])
        # Stop once the pack is full (merged packs list more subjects than they need).
        if sum(map(good, made)) >= PACK_SIZE or (spare and not client and len(made) >= PACK_SIZE):
            break
        print(f"{'Spare' if spare else 'Subject'} {k + 1}: {subject['name']}")
        board = best_board(subject, lambda **kw: backdrops.pick_themes(groups, used, recent, **kw),
                           taken | {B["source"]["id"] for B in made},
                           others_sigs + [set(B["sig"]) for B in made], client)
        if not board:
            print("   -> no usable image")
            continue
        made.append(board)
        i = names.index(board["theme"])
        used[i] = board["variant"] + 1
        recent = (recent + [i])[-12:]
        print(f"   -> {board['theme']} #{board['variant'] + 1}" + ("" if good(board) else "  (didn't pass)"))
    # Passing boards in subject order; if short, the best of the rest that Claude still named fill in (never one
    # it couldn't name: a pack is better a board short than with a board nobody can make out). Dropped boards are listed.
    keep = [B for B in made if good(B)][:PACK_SIZE]
    rest = sorted([B for B in made if not good(B) and (not client or (B["check"].get("score") or 0) >= 50)],
                  key=lambda B: -(B.get("check", {}).get("score") or 0))
    keep += rest[: PACK_SIZE - len(keep)]
    keep.sort(key=made.index)
    for B in made:
        if B not in keep:
            print(f"   dropped {B['name']} (score {B.get('check', {}).get('score')})")
    checks = {}
    levels = []
    for n, B in enumerate(keep, start):
        B = touch_up(dict(B, id=f"{B['name'].lower().replace(' ', '-')}-{n + 1}"))
        allsig[B["id"]] = B.pop("sig")
        check = B.pop("check", None)
        if check and not B.get("touched"):
            checks[B["id"]] = check
        levels.append({k: B[k] for k in ("id", "name", "rows", "theme", "variant", "source")}
                      | ({"touched": True} if B.get("touched") else {}))
    # Keep packs in the queue's order (Farm first), so rebuilding one doesn't renumber the others' levels.
    order = ["farm"] + [p["id"] for p in json.load(open(os.path.join(HERE, "packs", "queue.json")))["packs"]]
    data["packs"] = sorted(others + [{"id": spec["id"], "name": spec["name"], "levels": levels}],
                           key=lambda p: order.index(p["id"]) if p["id"] in order else len(order))
    json.dump(allsig, open(sigfile, "w"))
    json.dump(data, open(BOARDS, "w"), separators=(",", ":"))
    if client:
        # Save the blind-check answers where check_boards.py keeps them, so it doesn't ask again.
        checks_dir = os.path.join(HERE, "packs", "checks")
        os.makedirs(checks_dir, exist_ok=True)
        json.dump(checks, open(os.path.join(checks_dir, spec["id"] + ".json"), "w"), indent=1)
    out = os.path.splitext(sheet_base)[0] + "-sheet.png"
    sheet(levels, out)
    passed = sum(1 for c in checks.values() if c.get("grade") == "pass")
    print(f"Wrote {len(levels)} boards to {BOARDS}" + (f" ({passed} pass the blind check)" if client else "")
          + f"; review sheet {out}")


if __name__ == "__main__":
    main()
