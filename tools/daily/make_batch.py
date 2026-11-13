#!/usr/bin/env python3
"""Daily batch: pick new subjects, generate pictures, turn them into boards, judge them, and send the best to the
Board Reviewer app (the private queue repo).

    tools/.venv/bin/python tools/daily/make_batch.py [--date 2026-11-12] [--subjects 10] [--seeds 6] [--dry-run]

Steps (each one resumes if a run was stopped part way, keyed by date under STATE/runs/<date>/):
  1. Claude proposes `subjects_per_day` subjects in the style of Brian's 5-star boards, none used before.
  2. gen_images.py makes `seeds` pictures of each on this Mac (Z-Image-Turbo, ~1 min each).
  3. scene_to_board converts them; boards whose subject is cut off or tiny are dropped.
  4. The judge (calibrated to Brian's ratings) rates each; the best `per_subject` per subject with at least
     `min_stars` go to queue.json in the queue repo.
"""
import argparse
import datetime
import json
import os
import subprocess
import sys

from common import CFG, QUEUE, ROOT, RUNS, TOOLS, ensure_clone, load, log, push, save

sys.path.insert(0, TOOLS)

PROPOSE = """You choose subjects for a kids' puzzle game. Each subject becomes a 40x40 pixel-art picture: a cartoon
illustration is generated, then shrunk to 40x40 blocks in a 20-color palette.

The designer's ratings of past boards show what works:
- 5 stars: a cute full-body character with a face and big eyes (animals, creatures, friendly monsters, characters
  with jobs), or a richly detailed chunky vehicle, standing on a simple sky-and-grass or fitting backdrop.
- 2-3 stars: landmarks and buildings, plain objects, round things that fill the board as one flat shape (balls,
  cookies), subjects the same color as their backdrop (a green caterpillar on grass), mostly-white subjects.

Propose {n} NEW subjects. Mix animals, fantasy creatures, characters and vehicles; vary colors and settings across the
set. Never reuse or closely repeat these existing names: {used}.

For each give:
- name: 1-3 words, Title Case, what the board is called in the game (e.g. "Red Panda")
- thing: a vivid one-line description for the image generator: a cute, chubby, full-body {{subject}} with a friendly
  face, its pose, and its main colors (with darker shading), e.g. "a chubby cartoon red panda cub sitting up and
  waving, rusty orange fur with darker brown legs, a cream face mask and a ringed bushy tail"
- scene: 3-4 big, simple backdrop features that suit it and contrast with its colors, e.g. "a bright blue sky, two
  puffy white clouds, a green bamboo stalk, a grassy hill"."""

SCHEMA = {
    "type": "object",
    "properties": {"subjects": {"type": "array", "items": {
        "type": "object",
        "properties": {"name": {"type": "string"}, "thing": {"type": "string"}, "scene": {"type": "string"}},
        "required": ["name", "thing", "scene"], "additionalProperties": False}}},
    "required": ["subjects"],
    "additionalProperties": False,
}


def used_names():
    """Every board name in the game plus every subject the pipeline has tried."""
    res = os.path.join(ROOT, "Engine/Sources/ChipmunkEngine/Resources")
    names = set()
    for f in ("levels.json", "boards.json"):
        d = load(os.path.join(res, f), {})
        for p in d.get("packs", []):
            names.update(L["name"] for L in p["levels"])
        names.update(R["name"] for R in d.get("replace", {}).values())
    names.update(load(os.path.join(QUEUE, "tried.json"), []))
    return names


def propose(n, used):
    import anthropic
    from judge_boards import MODEL
    r = anthropic.Anthropic().beta.messages.create(
        model=MODEL,
        max_tokens=6000,
        output_config={"effort": "medium", "format": {"type": "json_schema", "schema": SCHEMA}},
        betas=["server-side-fallback-2026-07-01"],
        fallbacks="default",
        messages=[{"role": "user", "content": PROPOSE.format(n=n, used=", ".join(sorted(used)))}],
    )
    out = json.loads(next(b.text for b in r.content if b.type == "text"))["subjects"]
    low = {u.lower() for u in used}
    seen, keep = set(), []
    for s in out:
        k = s["name"].strip().lower()
        if k not in low and k not in seen:
            seen.add(k)
            keep.append(dict(s, name=s["name"].strip()))
    return keep[:n]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--date", default=datetime.date.today().isoformat())
    ap.add_argument("--subjects", type=int, default=8)
    ap.add_argument("--seeds", type=int, default=CFG["seeds"])
    ap.add_argument("--dry-run", action="store_true", help="build and judge, but don't push to the queue")
    a = ap.parse_args()

    ensure_clone(QUEUE, CFG["queue_repo"])
    run = os.path.join(RUNS, a.date)
    spec = os.path.join(run, "subjects.json")
    if not os.path.exists(spec):
        subjects = propose(a.subjects, used_names())
        save(spec, {"date": a.date, "subjects": subjects}, indent=1)
        # Record them as tried right away, so a crash doesn't make tomorrow pick them again.
        tried = load(os.path.join(QUEUE, "tried.json"), [])
        save(os.path.join(QUEUE, "tried.json"), sorted(set(tried) | {s["name"] for s in subjects}), indent=0)
        if not a.dry_run:
            push(QUEUE, "main", f"Subjects for {a.date}", ["tried.json"])
    subjects = json.load(open(spec))["subjects"]
    log(f"{len(subjects)} subjects:", ", ".join(s["name"] for s in subjects))

    gen = os.path.join(run, "gen")
    subprocess.run([sys.executable, os.path.join(TOOLS, "gen_images.py"), spec, "--seeds", str(a.seeds),
                    "--out", gen], check=True)

    import pilot_boards as pb
    from gen_images import slug
    boards = pb.convert_all(subjects, gen)
    judge = pb.make_judge()
    picked = []
    for s in subjects:
        cands = []
        for path, rows, info in boards.get(s["name"], []):
            if not pb.usable(info):
                continue
            try:
                cands.append((judge.rate(s["name"], rows), path, rows, info))
            except Exception as e:  # noqa: BLE001
                log("judge error", s["name"], path, e)
        cands.sort(key=lambda c: (-c[0]["stars"], -c[3]["subject"]))
        good = [c for c in cands if c[0]["stars"] >= CFG["min_stars"]][:CFG["per_subject"]]
        log(f"  {s['name']:16s} {len(cands)} usable, judged {[c[0]['stars'] for c in cands]}, sending {len(good)}")
        for j, path, rows, info in good:
            seed = os.path.basename(path)[:-4]
            picked.append(dict(id=f"new-{a.date}-{slug(s['name'])}-{seed}", name=s["name"], rows=rows,
                               judge=j["stars"], reason=j["reason"], batch=a.date, thing=s["thing"]))
    save(os.path.join(run, "picked.json"), picked, indent=1)
    if a.dry_run:
        log(f"dry run: {len(picked)} boards would go to the queue")
        return

    ensure_clone(QUEUE, CFG["queue_repo"])
    qpath = os.path.join(QUEUE, "queue.json")
    queue = load(qpath, [])
    have = {b["id"] for b in queue}
    new = [b for b in picked if b["id"] not in have]
    save(qpath, queue + new, indent=0)
    push(QUEUE, "main", f"{len(new)} new boards for review ({a.date})", ["queue.json"])
    log(f"queued {len(new)} boards; {len(queue) + len(new)} waiting for review")


if __name__ == "__main__":
    main()
