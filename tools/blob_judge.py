"""The board maker's judge, without Claude: it scores a board by its blobs (runs of same-colored blocks joined edge to
edge, blob_stats.py) and learns what Brian likes from his own answers.

Tested 2026-11-21 on his 310 Board Review decisions: the share of blocks in a board's 3 biggest blobs alone ranked
approved boards above denied ones 73% of the time, against 57% for the Claude judge. Boards with a few huge flat blobs
(sky, grass, a flat-colored subject) get denied; boards broken into many mid-sized blobs get approved.

`BlobJudge(history)` fits a small logistic model on
  - his Board Review decisions (history.jsonl in the queue repo), which grow every day, and
  - his 1-5 star ratings of the original boards (packs/blob-ratings.json, frozen), 4-5 stars as "approve" and
    1-2 as "deny", weighted lower,
using the 3-biggest-blobs share plus single blocks (plain and squared), so it can learn a "too fiddly" end once boards like that get reviewed (the
maker sends some on purpose: exploration boards).

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
    # single blocks, plain and squared: a curve with room for a "too fiddly" end, which only exploration boards can
    # show (no board reviewed by 2026-11-21 had more than 10% single blocks)
    ("share_in_1", lambda f: f["share_in_1"]),
    ("share_in_1_sq", lambda f: f["share_in_1"] ** 2),
]
RATING_WEIGHT = 0.3  # an old star rating counts less than a Board Review decision


def x(f):
    return [t(f) for _, t in TERMS]


class BlobJudge:
    def __init__(self, history=(), use_ratings=True):
        from sklearn.linear_model import LogisticRegression
        from sklearn.pipeline import make_pipeline
        from sklearn.preprocessing import StandardScaler
        X, y, w = [], [], []
        if use_ratings:
            for r in json.load(open(RATINGS)):
                if r["stars"] != 3:
                    X.append(x(r["f"]))
                    y.append(r["stars"] >= 4)
                    w.append(RATING_WEIGHT)
        self.decisions = 0
        for b in history:
            if b.get("decision") in ("approve", "deny") and b.get("rows"):
                X.append(x(features(b["rows"])))
                y.append(b["decision"] == "approve")
                w.append(1.0)
                self.decisions += 1
        self.model = make_pipeline(StandardScaler(), LogisticRegression(C=0.5, max_iter=2000))
        self.model.fit(np.array(X), np.array(y), logisticregression__sample_weight=np.array(w))
        self.trained_on = len(y)

    def p(self, f):
        return float(self.model.predict_proba(np.array([x(f)]))[0, 1])

    def rate(self, rows):
        f = features(rows)
        p = self.p(f)
        stars = 1 + sum(p >= c for c in (0.45, 0.6, 0.75, 0.85))
        reason = (f"Blob score {p:.0%}: biggest 3 blobs cover {f['top3_share']:.0%} of the board, "
                  f"{f['blobs_10_up']} blobs of 10+ blocks, {f['share_in_1']:.0%} single blocks.")
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
        pred[te] = [j.p(features(h[i]["rows"])) for i in te]
    print(f"{len(h)} decisions; blob judge AUC {auc(pred, y):.3f} (Claude judge "
          f"{auc([b.get('judge', 0) for b in h], y):.3f})")
    for cut in (0.55, 0.6, 0.65, 0.7, 0.75, 0.8):
        m = pred >= cut
        print(f"  send if p >= {cut}: {m.mean():.0%} of boards, {y[m].mean():.0%} approved")
