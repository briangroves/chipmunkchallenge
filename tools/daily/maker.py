#!/usr/bin/env python3
"""The board maker, running nonstop: one subject at a time, generate pictures, turn them into boards, judge them, and
hold the best; every `push_hours` push what it holds to the queue the Board Review app reads.

    tools/.venv/bin/python tools/daily/maker.py            # forever (launchd keeps it running)
    tools/.venv/bin/python tools/daily/maker.py --once     # one subject, then push (for testing)

It pauses while `max_waiting` boards (queued plus held) are waiting for review, so a backlog doesn't grow without
end, and resumes when Brian reviews. Everything resumes after a restart: subjects not finished yet
(STATE/subjects.json), boards not pushed yet (STATE/outbox.json), pictures already made (STATE/gen/<subject>/).
"""
import argparse
import json
import os
import sys
import time

from common import CFG, QUEUE, STATE, TOOLS, ensure_clone, load, log, push, save

sys.path.insert(0, TOOLS)
from make_batch import propose, used_names  # noqa: E402

GEN = os.path.join(STATE, "gen")
SUBJECTS = os.path.join(STATE, "subjects.json")   # proposed, not made yet
OUTBOX = os.path.join(STATE, "outbox.json")       # judged and picked, not pushed yet
LAST_PUSH = os.path.join(STATE, "last-push")


class Painter:
    """Z-Image-Turbo kept loaded, so each picture costs only its own generation time."""

    def __init__(self):
        from gen_images import MODEL
        from mflux.models.common.config import ModelConfig
        from mflux.models.z_image import ZImage
        self.model = ZImage(model_config=ModelConfig.z_image_turbo(), model_path=MODEL)

    def paint(self, s, seed, path):
        from gen_images import prompt
        t = time.time()
        img = self.model.generate_image(seed=seed * 1000 + len(s["name"]), prompt=prompt(s),
                                        num_inference_steps=CFG.get("steps", 9),
                                        width=CFG.get("size", 768), height=CFG.get("size", 768))
        img.save(path + ".tmp.png")
        os.replace(path + ".tmp.png", path)
        log(f"  {s['name']} seed {seed}: {time.time() - t:.0f}s")


def next_subject():
    """The next subject to make, asking Claude for a fresh handful when the list runs out."""
    todo = load(SUBJECTS, [])
    if not todo:
        ensure_clone(QUEUE, CFG["queue_repo"])
        todo = propose(CFG.get("propose_at_once", 8), used_names())
        save(SUBJECTS, todo, indent=1)
        # Mark them tried right away, so they're never proposed again even if the Mac restarts.
        tried = load(os.path.join(QUEUE, "tried.json"), [])
        save(os.path.join(QUEUE, "tried.json"), sorted(set(tried) | {s["name"] for s in todo}), indent=0)
        push(QUEUE, "main", f"Subjects: {', '.join(s['name'] for s in todo)}", ["tried.json"])
        log("new subjects:", ", ".join(s["name"] for s in todo))
    return todo[0]


def done_subject(s):
    save(SUBJECTS, [t for t in load(SUBJECTS, []) if t["name"] != s["name"]], indent=1)


def make(s, painter, judge):
    """Pictures -> boards -> judged; the best `per_subject` with at least `min_stars`."""
    import pilot_boards as pb
    from gen_images import slug
    d = os.path.join(GEN, slug(s["name"]))
    os.makedirs(d, exist_ok=True)
    for seed in range(1, CFG["seeds"] + 1):
        path = os.path.join(d, f"s{seed}.png")
        if not os.path.exists(path):
            painter.paint(s, seed, path)
    cands = []
    for path, rows, info in pb.convert_all([s], GEN).get(s["name"], []):
        if not pb.usable(info):
            continue
        try:
            cands.append((judge.rate(s["name"], rows), path, rows, info))
        except Exception as e:  # noqa: BLE001
            log("  judge error", path, e)
    cands.sort(key=lambda c: (-c[0]["stars"], -c[3]["subject"]))
    good = [c for c in cands if c[0]["stars"] >= CFG["min_stars"]][:CFG["per_subject"]]
    log(f"{s['name']}: judged {[c[0]['stars'] for c in cands]}, keeping {len(good)}")
    day = time.strftime("%Y-%m-%d")
    return [dict(id=f"new-{day}-{slug(s['name'])}-{os.path.basename(p)[:-4]}", name=s["name"], rows=rows,
                 judge=j["stars"], reason=j["reason"], batch=day, thing=s["thing"]) for j, p, rows, _ in good]


def code_moved_on():
    """True when the branch this copy runs has newer pushes (then the maker exits and launchd restarts it on them).
    Only for the pipeline's own copy (run.sh), never a checkout someone is working in."""
    from common import ROOT, git
    if os.path.basename(ROOT) != "code" or not os.path.exists(os.path.join(STATE, "branch")):
        return False
    branch = open(os.path.join(STATE, "branch")).read().strip()
    try:
        git(ROOT, "fetch", "-q", "origin", branch)
        return git(ROOT, "rev-parse", "HEAD") != git(ROOT, "rev-parse", f"origin/{branch}")
    except Exception:  # noqa: BLE001  (offline: keep going on what we have)
        return False


def waiting():
    """Boards waiting for review: in the queue repo (as of the last fetch) plus held here."""
    return len(load(os.path.join(QUEUE, "queue.json"), [])) + len(load(OUTBOX, []))


def push_due(force=False):
    last = float(open(LAST_PUSH).read()) if os.path.exists(LAST_PUSH) else 0
    if not force and time.time() - last < CFG["push_hours"] * 3600:
        return
    out = load(OUTBOX, [])
    ensure_clone(QUEUE, CFG["queue_repo"])
    if out:
        qpath = os.path.join(QUEUE, "queue.json")
        queue = load(qpath, [])
        have = {b["id"] for b in queue}
        new = [b for b in out if b["id"] not in have]
        save(qpath, queue + new, indent=0)
        push(QUEUE, "main", f"{len(new)} new board{'s' * (len(new) != 1)} for review", ["queue.json"])
        save(OUTBOX, [], indent=0)
        log(f"pushed {len(new)} boards; {len(queue) + len(new)} waiting for review")
    with open(LAST_PUSH, "w") as f:
        f.write(str(time.time()))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--once", action="store_true")
    a = ap.parse_args()
    import pilot_boards as pb
    ensure_clone(QUEUE, CFG["queue_repo"])
    painter, judge = None, None
    while True:
        try:
            push_due(force=a.once)
            if a.once and painter is not None:
                return
            if waiting() >= CFG["max_waiting"]:
                log(f"{waiting()} boards waiting for review; pausing")
                time.sleep(1800)
                ensure_clone(QUEUE, CFG["queue_repo"])
                continue
            if painter is None:
                painter, judge = Painter(), pb.make_judge()
            s = next_subject()
            picked = make(s, painter, judge)
            save(OUTBOX, load(OUTBOX, []) + picked, indent=0)
            done_subject(s)
            if code_moved_on():
                log("newer code pushed; restarting on it")
                return
        except KeyboardInterrupt:
            raise
        except Exception as e:  # noqa: BLE001  (network down, API hiccup: wait and carry on)
            log("error:", repr(e))
            if a.once:
                raise
            time.sleep(600)


if __name__ == "__main__":
    main()
