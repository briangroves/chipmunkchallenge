#!/usr/bin/env python3
"""Board-maker pilot: turn every generated picture into a board, score each with the judge calibrated to Brian's
ratings, and keep the best board per subject.

    zsh -lic "tools/.venv/bin/python tools/pilot_boards.py tools/pilot/subjects.json"

Pictures come from gen_images.py (~/Library/Caches/chipmunk-boards/gen/<subject>/s<seed>.png). A board is dropped
before judging if its subject is cut off by the picture's edge or covers too little of the board. Writes
tools/pilot/boards.json (every judged board, best first per subject) and tools/pilot/compare.png (old board, then
the best three new ones, per subject), and the best two per subject to the app's Board review
(ios/ChipmunkChallenge/Native/pilot-boards.json).
"""
import argparse
import csv
import json
import os
import sys
from concurrent.futures import ThreadPoolExecutor

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import judge_boards as jb  # noqa: E402
import scene_to_board as stb  # noqa: E402
from gen_images import OUT as GEN, slug  # noqa: E402
from image_to_board import RGB  # noqa: E402

RATINGS = os.path.join(HERE, "packs", "ratings-2026-11-10.csv")
APP = os.path.join(os.path.dirname(HERE), "ios/ChipmunkChallenge/Native/pilot-boards.json")
PER_SUBJECT = 2
PILOT = os.path.join(HERE, "pilot")
# Brian's ratings of the first pilot round, and the ones the judge learns from: every board it overrated, plus a spread
# of 5s down to 2s, so it sees what he thinks of boards in the new style.
ROUND1 = os.path.join(PILOT, "rated-round1.json")
ROUND1_EXAMPLES = ["pilot-polar-bear-s6", "pilot-soccer-ball-s4", "pilot-soccer-ball-s3", "pilot-cookie-s5",
                   "pilot-unicorn-s1", "pilot-fire-truck-s5", "pilot-robot-s5", "pilot-hedgehog-s3", "pilot-guitar-s1",
                   "pilot-cookie-s6", "pilot-paris-s1", "pilot-caterpillar-s4", "pilot-castle-s5", "pilot-london-s5",
                   "pilot-skateboard-s6"]


# The example boards' rows as Brian rated them (25 colors), frozen here because the game's board files have since
# moved on (19 colors, original boards retired).
EXAMPLE_ROWS = os.path.join(HERE, "packs", "judge-examples.json")


def make_judge():
    """The judge, shown the old boards' examples plus Brian's ratings of new-style boards."""
    import anthropic
    examples, _ = jb.split(jb.load_ratings(RATINGS))
    rows = json.load(open(EXAMPLE_ROWS))
    rated = {b["id"]: b for b in json.load(open(ROUND1))}
    for i in ROUND1_EXAMPLES:
        examples.append(dict(id=i, name=rated[i]["name"], stars=rated[i]["stars"]))
    return jb.Judge(anthropic.Anthropic(), examples, rows)


def convert_all(subjects, gen=GEN):
    """{subject name: [(seed path, rows, info)]}, converting pictures not converted yet (cached next to them)."""
    out = {}
    for s in subjects:
        d = os.path.join(gen, slug(s["name"]))
        fill = s.get("fill", stb.FILL)
        out[s["name"]] = []
        if not os.path.isdir(d):
            continue
        for f in sorted(os.listdir(d)):
            if not (f.startswith("s") and f.endswith(".png")) or ".tmp" in f:
                continue
            path = os.path.join(d, f)
            cache = path[:-4] + ".board.json"
            b = None
            if os.path.exists(cache) and os.path.getmtime(cache) >= os.path.getmtime(stb.__file__):
                b = json.load(open(cache))
                if b["rows"] and b["info"].get("fill", stb.FILL) != fill:
                    b = None
            if b is None:
                rows, info = stb.convert(path, fill)
                b = {"rows": rows, "info": info}
                json.dump(b, open(cache, "w"))
            if b["rows"]:
                out[s["name"]].append((path, b["rows"], b["info"]))
    return out


def usable(info):
    return not info["cut"] and not info["touches"] and info["subject"] >= 0.10


def old_boards(subjects):
    """Each subject's current board (the one Brian rated), matched by name and his rating."""
    rated = list(csv.DictReader(open(RATINGS)))
    rows = jb.all_rows()
    out = {}
    for s in subjects:
        m = next((r for r in rated if r["name"] == s["name"] and int(r["stars"]) == s["old"]), None)
        if m and m["id"] in rows:
            out[s["name"]] = rows[m["id"]]
    return out


def compare_sheet(subjects, old, best, out, z=5):
    """One row per subject: the old board, a gap, then the best new boards with their judged stars as bars."""
    from PIL import Image, ImageDraw
    n, tile, gap, label = 40, 40 * z, 8, 18
    cols = 4
    img = Image.new("RGB", (190 + cols * (tile + gap) + gap, len(subjects) * (tile + label + gap) + gap), (32, 32, 32))
    d = ImageDraw.Draw(img)
    for i, s in enumerate(subjects):
        oy = gap + i * (tile + label + gap)
        d.text((8, oy + tile // 2 - 14), s["name"], fill=(255, 255, 255))
        d.text((8, oy + tile // 2 + 2), f"old: {s['old']} star", fill=(200, 200, 200))
        boards = ([("old", old.get(s["name"]), None)] +
                  [("new", b["rows"], b["judge"]["stars"]) for b in best.get(s["name"], [])[:cols - 1]])
        for j, (kind, rows, stars) in enumerate(boards):
            if not rows:
                continue
            ox = 190 + gap + j * (tile + gap)
            for r, row in enumerate(rows):
                for c, ch in enumerate(row):
                    d.rectangle([ox + c * z, oy + r * z, ox + c * z + z - 1, oy + r * z + z - 1], fill=RGB[ch])
            text = "current board" if kind == "old" else f"judge: {stars} star"
            d.text((ox, oy + tile + 3), text, fill=(255, 220, 90) if kind == "new" else (180, 180, 180))
    img.save(out)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("spec")
    ap.add_argument("--gen", default=GEN, help="folder the pictures are in")
    a = ap.parse_args()
    subjects = json.load(open(a.spec))["subjects"]
    boards = convert_all(subjects, a.gen)
    judge = make_judge()
    jobs = [(name, p, rows, info) for name, bs in boards.items() for p, rows, info in bs if usable(info)]
    dropped = sum(len(bs) for bs in boards.values()) - len(jobs)

    def go(job):
        name, p, rows, info = job
        try:
            return dict(name=name, image=p, rows=rows, info=info, judge=judge.rate(name, rows))
        except Exception as e:  # noqa: BLE001
            print("  error", name, p, e, file=sys.stderr)
            return None

    with ThreadPoolExecutor(6) as pool:
        judged = [j for j in pool.map(go, jobs) if j]
    best = {}
    for j in judged:
        best.setdefault(j["name"], []).append(j)
    for name in best:
        best[name].sort(key=lambda j: (-j["judge"]["stars"], -j["info"]["subject"]))
    os.makedirs(PILOT, exist_ok=True)
    json.dump({s["name"]: best.get(s["name"], []) for s in subjects}, open(os.path.join(PILOT, "boards.json"), "w"),
              indent=1)
    # The app's Board review shows these first: the best PER_SUBJECT of each subject, in a fixed shuffled order.
    import random
    app = [dict(id=f"pilot-{slug(name)}-{os.path.basename(j['image'])[:-4]}", name=name, rows=j["rows"],
                judge=j["judge"]["stars"], reason=j["judge"]["reason"])
           for name, js in best.items() for j in js[:PER_SUBJECT]]
    random.Random(11).shuffle(app)
    json.dump(app, open(APP, "w"))
    compare_sheet(subjects, old_boards(subjects), best, os.path.join(PILOT, "compare.png"))
    print(f"{len(judged)} boards judged ({dropped} dropped: subject cut off or too small)")
    for s in subjects:
        top = best.get(s["name"], [])
        dist = [j["judge"]["stars"] for j in top]
        print(f"  {s['name']:12s} old {s['old']}  best {dist[0] if dist else '-'}  all {dist}"
              + (f"  - {top[0]['judge']['reason']}" if top else ""))


if __name__ == "__main__":
    main()
