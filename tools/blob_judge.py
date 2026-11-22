"""The board maker's judge, without Claude: it scores a board by its blobs (runs of same-colored blocks joined edge to
edge, blob_stats.py) and learns what Brian likes from his own answers.

Tested 2026-11-21 on his 310 Board Review decisions: the share of blocks in a board's 3 biggest blobs alone ranked
approved boards above denied ones 73% of the time, against 57% for the Claude judge. Boards with a few huge flat blobs
(sky, grass, a flat-colored subject) get denied; boards broken into many mid-sized blobs get approved.

`BlobJudge(history)` fits a small logistic model on
  - his Board Review decisions (history.jsonl in the queue repo), which grow every day, and
  - his 1-5 star ratings of the original boards (packs/blob-ratings.json, frozen), 4-5 stars as "approve" and
    1-2 as "deny", weighted much lower,
using the 3-biggest-blobs share, how often side-by-side blocks differ (edge_density), how many blobs have 10+ blocks,
and single blocks (plain and squared), so it can learn a "too fiddly" end once boards like that get reviewed (the
maker sends some on purpose: exploration boards).

What it can't see: most denials are about the picture (flat backdrop, no shading, no outline, hard-to-read face),
which blob stats only catch in part; it tops out near AUC 0.71.

`judge.rate(rows)` gives {"p": chance he approves, "stars": 1-5 for the Board Review app, "reason": one line,
"stats": the blob stats}.
"""
import json
import os

import numpy as np

from blob_stats import features

HERE = os.path.dirname(os.path.abspath(__file__))
RATINGS = os.path.join(HERE, "packs", "blob-ratings.json")

# The stats the model sees, each turned into a number by `x`.
TERMS = [
    ("top3_share", lambda f: f["top3_share"]),
    # added 2026-11-21 after the re-review of every board in the game (534 decisions): trained on the new boards
    # only, these two lifted AUC on the 224 re-reviewed game boards from 0.72 to 0.76
    ("edge_density", lambda f: f["edge_density"]),
    ("blobs_10_up", lambda f: f["blobs_10_up"]),
    # single blocks, plain and squared: a curve with room for a "too fiddly" end, which only exploration boards can
    # show (no board reviewed by 2026-11-21 had more than 10% single blocks)
    ("share_in_1", lambda f: f["share_in_1"]),
    ("share_in_1_sq", lambda f: f["share_in_1"] ** 2),
]
# An old star rating counts far less than a Board Review decision. Cut from 0.3 on 2026-11-21: with 534 decisions,
# the ratings dragged the edge_density/blobs_10_up terms back (AUC on game boards 0.754 at 0.1 vs 0.714 at 0.3).
RATING_WEIGHT = 0.1
# The picture-level CLIP score (vision_score.py), used when the model is on this Mac: "does it look like a cartoon
# animal with a clear face". Blob stats plus this: AUC on re-reviewed game boards 0.79 vs 0.76 without.
FACE_TERM = ("face", lambda f: f["face"])


def x(f, terms=None):
    return [t(f) for _, t in (terms or TERMS)]


class BlobJudge:
    def __init__(self, history=(), use_ratings=True, use_vision=True):
        from sklearn.linear_model import LogisticRegression
        from sklearn.pipeline import make_pipeline
        from sklearn.preprocessing import StandardScaler
        import vision_score
        self.vision = use_vision and vision_score.available()
        self.terms = TERMS + [FACE_TERM] * self.vision
        X, y, w = [], [], []
        if use_ratings:
            for r in json.load(open(RATINGS)):
                if r["stars"] != 3 and (not self.vision or "face" in r["f"]):
                    X.append(x(r["f"], self.terms))
                    y.append(r["stars"] >= 4)
                    w.append(RATING_WEIGHT)
        self.decisions = 0
        hist = [b for b in history if b.get("decision") in ("approve", "deny") and b.get("rows")]
        for b, f in zip(hist, self.feats([b["rows"] for b in hist])):
            X.append(x(f, self.terms))
            y.append(b["decision"] == "approve")
            w.append(1.0)
            self.decisions += 1
        self.model = make_pipeline(StandardScaler(), LogisticRegression(C=0.5, max_iter=2000))
        self.model.fit(np.array(X), np.array(y), logisticregression__sample_weight=np.array(w))
        self.trained_on = len(y)

    def feats(self, rows_list):
        """Blob stats for each board, plus the CLIP face score when the judge uses it."""
        fs = [features(rows) for rows in rows_list]
        if self.vision:
            import vision_score
            for f, s in zip(fs, vision_score.face(rows_list)):
                f["face"] = s
        return fs

    def p(self, f):
        return float(self.model.predict_proba(np.array([x(f, self.terms)]))[0, 1])

    def rate(self, rows):
        f = self.feats([rows])[0]
        p = self.p(f)
        stars = 1 + sum(p >= c for c in (0.45, 0.6, 0.75, 0.85))
        reason = (f"Blob score {p:.0%}: biggest 3 blobs cover {f['top3_share']:.0%} of the board, "
                  f"{f['blobs_10_up']} blobs of 10+ blocks, {f['share_in_1']:.0%} single blocks, "
                  f"{f['edge_density']:.0%} of neighbors differ"
                  + (f", face score {f['face']:+.3f}." if self.vision else "."))
        return dict(p=round(p, 4), stars=int(stars), reason=reason, stats={k: round(float(v), 4) for k, v in f.items()})


if __name__ == "__main__":
    # How well it does: cross-validated on the Board Review decisions.
    import sys
    sys.path.insert(0, os.path.join(HERE, "daily"))
    from feedback import history
    from blob_stats import auc
    from sklearn.model_selection import StratifiedKFold
    h = history()
    y = np.array([b["decision"] == "approve" for b in h])
    pred = np.zeros(len(h))
    for tr, te in StratifiedKFold(5, shuffle=True, random_state=0).split(np.zeros(len(h)), y):
        j = BlobJudge([h[i] for i in tr])
        pred[te] = [j.p(f) for f in j.feats([h[i]["rows"] for i in te])]
    print(f"vision {'on' if j.vision else 'off'}; {len(h)} decisions; blob judge AUC {auc(pred, y):.3f} (Claude judge "
          f"{auc([b.get('judge', 0) for b in h], y):.3f})")
    for cut in (0.55, 0.6, 0.65, 0.7, 0.75, 0.8):
        m = pred >= cut
        print(f"  send if p >= {cut}: {m.mean():.0%} of boards, {y[m].mean():.0%} approved")
