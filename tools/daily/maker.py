#!/usr/bin/env python3
"""The board maker: one subject at a time, generate pictures, turn them into boards, judge them by their blobs, and
hold the best; once a day (at `push_at` o'clock) push the day's boards to the queue the Board Review app reads.

    tools/.venv/bin/python tools/daily/maker.py            # forever (launchd keeps it running)
    tools/.venv/bin/python tools/daily/maker.py --once     # one subject, then push (for testing)

The judge (blob_judge.py) runs on this Mac and never calls Claude. It's refit before each subject from Brian's
Board Review decisions, so it keeps learning. Claude is only asked for new subject ideas, `propose_at_once` at a time.

Daily batch: the maker paints until it holds `daily_boards` boards, then rests until the push. It also rests while
`max_waiting` boards (queued plus held) wait for review.

Exploration: about `explore_rate` of subjects send a board the judge would normally hold back (the most fragmented
one, or the one it likes least), marked "explore": true. Brian's answers on those teach the judge where "too fiddly"
and "too flat" really start, which boards it already likes can never show.

Saving time: a subject's pictures are judged as they're painted; once `min_seeds` are done and one scores at least
`good_enough`, the rest aren't painted.

Everything resumes after a restart: subjects not finished yet (STATE/subjects.json), boards not pushed yet
(STATE/outbox.json), pictures already made (STATE/gen/<subject>/).
"""
import argparse
import datetime
import os
import random
import sys
import time

from common import CFG, QUEUE, STATE, TOOLS, ensure_clone, load, log, push, save

sys.path.insert(0, TOOLS)
from feedback import history  # noqa: E402
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
        todo = propose(CFG.get("propose_at_once", 20), used_names())
        save(SUBJECTS, todo, indent=1)
        # Mark them tried right away, so they're never proposed again even if the Mac restarts.
        tried = load(os.path.join(QUEUE, "tried.json"), [])
        save(os.path.join(QUEUE, "tried.json"), sorted(set(tried) | {s["name"] for s in todo}), indent=0)
        push(QUEUE, "main", f"Subjects: {', '.join(s['name'] for s in todo)}", ["tried.json"])
        log("new subjects:", ", ".join(s["name"] for s in todo))
    return todo[0]


def done_subject(s):
    save(SUBJECTS, [t for t in load(SUBJECTS, []) if t["name"] != s["name"]], indent=1)


def judged(s, judge):
    """[(rating, path, rows)] for the subject's usable boards painted so far."""
    import pilot_boards as pb
    return [(judge.rate(rows), path, rows) for path, rows, info in pb.convert_all([s], GEN).get(s["name"], [])
            if pb.usable(info)]


def make(s, painter, judge, explore=False):
    """Pictures -> boards -> judged. Normally the best board if the judge gives it at least `min_p` (and it isn't
    more fragmented than `frag_max`); for an exploration subject, a board from outside that range."""
    from gen_images import slug
    d = os.path.join(GEN, slug(s["name"]))
    os.makedirs(d, exist_ok=True)
    cands, painted = [], 0
    for seed in range(1, CFG["seeds"] + 1):
        path = os.path.join(d, f"s{seed}.png")
        if not os.path.exists(path):
            painter.paint(s, seed, path)
            painted += 1
        if not explore and seed >= CFG.get("min_seeds", 3):
            cands = judged(s, judge)
            if any(c[0]["p"] >= CFG.get("good_enough", 0.7) for c in cands):
                break
    cands = judged(s, judge)
    frag = CFG.get("frag_max", 0.15)
    if explore and cands:
        # Half the time the most fragmented board (where "too fiddly" might start), else the one it likes least.
        if random.random() < 0.5:
            pick = max(cands, key=lambda c: c[0]["stats"]["share_in_1"])
        else:
            pick = min(cands, key=lambda c: c[0]["p"])
        good = [pick]
    else:
        ok = [c for c in cands if c[0]["p"] >= CFG["min_p"] and c[0]["stats"]["share_in_1"] <= frag]
        good = sorted(ok, key=lambda c: -c[0]["p"])[:CFG["per_subject"]]
    log(f"{s['name']}{' (exploring)' if explore else ''}: {painted} painted, judged "
        f"{[round(c[0]['p'], 2) for c in cands]}, keeping {len(good)}")
    day = time.strftime("%Y-%m-%d")
    out = []
    for j, p, rows in good:
        b = dict(id=f"new-{day}-{slug(s['name'])}-{os.path.basename(p)[:-4]}", name=s["name"], rows=rows,
                 judge=j["stars"], reason=j["reason"], blob_p=j["p"], blobs=j["stats"], batch=day, thing=s["thing"])
        if explore:
            b["explore"] = True
        out.append(b)
    return out


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
    """New boards waiting for review: in the queue repo (as of the last fetch) plus held here. Boards already in the
    game, sent back for a second look (slots.py), don't count."""
    return (sum(1 for b in load(os.path.join(QUEUE, "queue.json"), []) if not b.get("audit"))
            + len(load(OUTBOX, [])))


def last_push_time(now=None):
    """The most recent daily push time (`push_at` o'clock) at or before now, as a timestamp."""
    now = now or datetime.datetime.now()
    t = now.replace(hour=CFG.get("push_at", 6), minute=0, second=0, microsecond=0)
    if t > now:
        t -= datetime.timedelta(days=1)
    return t.timestamp()


def push_due(force=False):
    last = float(open(LAST_PUSH).read()) if os.path.exists(LAST_PUSH) else 0
    if not force and last >= last_push_time():
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


def resting():
    """Why the maker should stop painting for now, or None."""
    if waiting() >= CFG["max_waiting"]:
        return f"{waiting()} boards waiting for review"
    if len(load(OUTBOX, [])) >= CFG.get("daily_boards", 40):
        return f"today's {len(load(OUTBOX, []))} boards are ready for the {CFG.get('push_at', 6)}:00 push"
    return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--once", action="store_true")
    ap.add_argument("--explore", action="store_true", help="with --once: make it an exploration subject")
    a = ap.parse_args()
    from blob_judge import BlobJudge
    ensure_clone(QUEUE, CFG["queue_repo"])
    painter, rested = None, None
    while True:
        try:
            push_due(force=a.once and painter is not None)
            if a.once and painter is not None:
                return
            why = resting()
            if why and not a.once:
                if why != rested:
                    log(f"{why}; resting")
                rested = why
                time.sleep(900)
                ensure_clone(QUEUE, CFG["queue_repo"])
                continue
            rested = None
            if painter is None:
                painter = Painter()
            # Refit each subject, so Brian's latest decisions count right away.
            ensure_clone(QUEUE, CFG["queue_repo"])
            judge = BlobJudge(history())
            s = next_subject()
            explore = a.explore if a.once else random.random() < CFG.get("explore_rate", 0.1)
            picked = make(s, painter, judge, explore)
            save(OUTBOX, load(OUTBOX, []) + picked, indent=0)
            done_subject(s)
            if code_moved_on():
                log("newer code pushed; restarting on it")
                return
        except KeyboardInterrupt:
            raise
        except Exception as e:  # noqa: BLE001  (network down, Claude busy for subjects: wait and carry on)
            log("error:", repr(e))
            if a.once:
                raise
            if code_moved_on():  # a fix may have been pushed for this very error
                log("newer code pushed; restarting on it")
                return
            time.sleep(600)


if __name__ == "__main__":
    main()
