#!/usr/bin/env python3
"""Blob statistics for boards: every run of same-colored blocks joined edge to edge (the game's 4-neighbor rule) is one
blob. `features(rows)` describes a board by how many blobs it has and how its blocks are spread over blob sizes.

    tools/.venv/bin/python tools/blob_stats.py      # test the stats against Brian's reviews and ratings

Data it tests against:
  - the Board Review history (approve / deny on new boards, with the Claude judge's stars), from the queue clone
  - Brian's 1-5 star ratings of the original boards (packs/ratings-2026-11-10.csv)
"""
import csv
import json
import math
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
STATE = os.path.expanduser("~/Library/Application Support/ChipmunkBoards")
EMPTY = set(". ")


def blobs(rows):
    """Sizes of every blob (same character, 4-connected), largest first."""
    H, W = len(rows), len(rows[0])
    seen = [[False] * W for _ in range(H)]
    sizes = []
    for r in range(H):
        for c in range(W):
            ch = rows[r][c]
            if seen[r][c] or ch in EMPTY:
                continue
            seen[r][c] = True
            stack, n = [(r, c)], 0
            while stack:
                y, x = stack.pop()
                n += 1
                for yy, xx in ((y - 1, x), (y + 1, x), (y, x - 1), (y, x + 1)):
                    if 0 <= yy < H and 0 <= xx < W and not seen[yy][xx] and rows[yy][xx] == ch:
                        seen[yy][xx] = True
                        stack.append((yy, xx))
            sizes.append(n)
    return sorted(sizes, reverse=True)


def features(rows):
    s = np.array(blobs(rows), float)
    total = s.sum()
    w = s / total                       # share of the board's blocks in each blob
    rest = s[1:]                        # without the biggest blob (usually the sky / backdrop)
    f = {
        "blobs": len(s),
        "blobs_per_100": 100 * len(s) / total,
        "colors": len(set("".join(rows)) - EMPTY),
        "mean_size": s.mean(),
        "median_size": float(np.median(s)),
        # the size of the blob a randomly picked block sits in: what a player mostly experiences
        "typical_size": float((s * w).sum()),
        "largest_share": w[0],
        "top3_share": w[:3].sum(),
        "share_in_1": w[s == 1].sum(),
        "share_in_2_3": w[(s >= 2) & (s <= 3)].sum(),
        "share_in_4_10": w[(s >= 4) & (s <= 10)].sum(),
        "share_in_11_50": w[(s >= 11) & (s <= 50)].sum(),
        "share_in_51_200": w[(s >= 51) & (s <= 200)].sum(),
        "share_in_200_up": w[s > 200].sum(),
        "singles": int((s == 1).sum()),
        "blobs_10_up": int((s >= 10).sum()),
        # spread of blob sizes, on a log scale (0 = all blobs the same size)
        "log_size_sd": float(np.log(s).std()),
        # how evenly blocks are spread over blobs: exp(entropy) = "effective number of blobs"
        "effective_blobs": float(math.exp(-(w * np.log(w)).sum())),
        "typical_size_no_bg": float((rest * rest / rest.sum()).sum()) if len(rest) else 0.0,
    }
    return f


# ---------------------------------------------------------------------------------------------------------------
# Testing against Brian's decisions

def auc(scores, labels):
    """Chance a random approved board scores above a random denied one (0.5 = no better than a coin)."""
    scores, labels = np.asarray(scores, float), np.asarray(labels, bool)
    pos, neg = scores[labels], scores[~labels]
    if not len(pos) or not len(neg):
        return float("nan")
    gt = (pos[:, None] > neg[None, :]).sum() + 0.5 * (pos[:, None] == neg[None, :]).sum()
    return gt / (len(pos) * len(neg))


def spearman(a, b):
    from scipy.stats import spearmanr
    return spearmanr(a, b).statistic


def load_history():
    h = [json.loads(l) for l in open(os.path.join(STATE, "queue", "history.jsonl")) if l.strip()]
    return [b for b in h if b.get("decision") in ("approve", "deny") and b.get("rows")]


RATED_AT = "c9666e9"   # the commit whose levels.json / boards.json hold the boards as Brian rated them


def old_rows():
    """{id: rows} for the boards in the game at RATED_AT (read from git, since the 20-color change replaced them)."""
    import subprocess
    res = "Engine/Sources/ChipmunkEngine/Resources"
    rows = {}
    for f in ("levels.json", "boards.json"):
        d = json.loads(subprocess.run(["git", "-C", HERE, "show", f"{RATED_AT}:{res}/{f}"], capture_output=True,
                                      text=True, check=True).stdout)
        for p in d.get("packs", []):
            rows.update({L["id"]: L["rows"] for L in p["levels"]})
        rows.update({R["id"]: R["rows"] for R in d.get("replace", {}).values()})
    return rows


def load_ratings():
    rows = old_rows()
    ex = os.path.join(STATE, "code", "tools", "packs", "judge-examples.json")
    if os.path.exists(ex):
        rows.update(json.load(open(ex)))
    out = []
    for r in csv.DictReader(open(os.path.join(HERE, "packs", "ratings-2026-11-10.csv"))):
        if r["id"] in rows:
            out.append(dict(id=r["id"], name=r["name"], stars=int(r["stars"]),
                            claude=int(r["claude_score"] or 0), rows=rows[r["id"]]))
    return out


def bins(values, labels, edges):
    out = []
    values, labels = np.asarray(values), np.asarray(labels, bool)
    for lo, hi in zip(edges[:-1], edges[1:]):
        m = (values >= lo) & (values < hi)
        if m.sum():
            out.append((lo, hi, int(m.sum()), labels[m].mean()))
    return out


if __name__ == "__main__":
    hist = load_history()
    X = [features(b["rows"]) for b in hist]
    y = [b["decision"] == "approve" for b in hist]
    print(f"{len(hist)} reviewed boards, {sum(y)} approved ({np.mean(y):.0%})")
    print("Claude judge stars vs your decision: AUC", round(auc([b["judge"] for b in hist], y), 3))
    print("\nOne stat at a time (AUC; 0.5 = useless, below 0.5 = lower is better):")
    for k in X[0]:
        print(f"  {k:20s} {auc([x[k] for x in X], y):.3f}   median {np.median([x[k] for x in X]):.3g}")
