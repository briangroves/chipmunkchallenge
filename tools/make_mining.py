#!/usr/bin/env python3
"""Make the Coin Mining boards with the new board maker (2026-11-12): fresh subjects, pictures on this Mac, boards in
the game's 20 colors, judged, the best board of each subject kept.

    tools/.venv/bin/python tools/make_mining.py [--subjects 22] [--seeds 3] [--keep 20] [--size 512]

Resumes where it stopped (state in ~/Library/Application Support/ChipmunkBoards/runs/mining/). Writes the boards to
Engine/Sources/ChipmunkEngine/Resources/boards.json under "mining", which Coin Mining plays in place of the original
pictures. Subjects are recorded as tried, so the always-on maker doesn't make them again.
"""
import argparse
import json
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "daily"))
sys.path.insert(0, HERE)
from common import QUEUE, ROOT, RUNS, load, log, save  # noqa: E402
import make_batch  # noqa: E402


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--subjects", type=int, default=22)
    ap.add_argument("--seeds", type=int, default=3)
    ap.add_argument("--keep", type=int, default=20)
    ap.add_argument("--size", type=int, default=512)
    a = ap.parse_args()

    run = os.path.join(RUNS, "mining")
    spec = os.path.join(run, "subjects.json")
    if not os.path.exists(spec):
        subjects = make_batch.propose(a.subjects, make_batch.used_names())
        save(spec, {"subjects": subjects}, indent=1)
        tried = load(os.path.join(QUEUE, "tried.json"), [])
        save(os.path.join(QUEUE, "tried.json"), sorted(set(tried) | {s["name"] for s in subjects}), indent=0)
    subjects = json.load(open(spec))["subjects"]
    log(f"mining: {len(subjects)} subjects:", ", ".join(s["name"] for s in subjects))

    gen = os.path.join(run, "gen")
    subprocess.run([sys.executable, os.path.join(HERE, "gen_images.py"), spec, "--seeds", str(a.seeds),
                    "--size", str(a.size), "--out", gen], check=True)

    import pilot_boards as pb
    from gen_images import slug
    boards = pb.convert_all(subjects, gen)
    judge = pb.make_judge()
    best = []
    for s in subjects:
        cands = []
        for path, rows, info in boards.get(s["name"], []):
            if not pb.usable(info):
                continue
            try:
                cands.append((judge.rate(s["name"], rows)["stars"], info["subject"], path, rows))
            except Exception as e:  # noqa: BLE001
                log("judge error", s["name"], path, e)
        log(f"  {s['name']:16s} judged {sorted((c[0] for c in cands), reverse=True)}")
        if cands:
            stars, size, path, rows = max(cands, key=lambda c: (c[0], c[1]))
            best.append(dict(id=f"mine-{slug(s['name'])}-{os.path.basename(path)[:-4]}", name=s["name"],
                             rows=rows, stars=stars))
    best.sort(key=lambda b: -b["stars"])
    keep = best[:a.keep]
    save(os.path.join(run, "picked.json"), keep, indent=1)

    res = os.path.join(ROOT, "Engine/Sources/ChipmunkEngine/Resources/boards.json")
    d = json.load(open(res))
    d["mining"] = [{"id": b["id"], "name": b["name"], "rows": b["rows"]} for b in keep]
    json.dump(d, open(res, "w"), separators=(",", ":"))
    log(f"mining: {len(keep)} boards (stars {[b['stars'] for b in keep]}) -> {res}")


if __name__ == "__main__":
    main()
