#!/usr/bin/env python3
"""Write the blind-check scores for every Level Play board into the app (board-scores.json), keyed by level id:
score (0-100), grade (pass/weak/fail) and what Claude guessed it was. The in-app board review screen shows them."""
import glob
import json
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RES = os.path.join(ROOT, "Engine/Sources/ChipmunkEngine/Resources")
out = {}
for f in sorted(glob.glob(os.path.join(ROOT, "tools/packs/checks/*.json"))):
    for k, v in json.load(open(f)).items():
        if isinstance(v, dict) and "score" in v:
            out[k] = {"s": v.get("score") or 0, "g": v.get("grade") or "", "q": v.get("guess") or ""}
ids = [L["id"] for p in json.load(open(os.path.join(RES, "levels.json")))["packs"] for L in p["levels"]]
nb = json.load(open(os.path.join(RES, "boards.json")))
ids = [nb.get("replace", {}).get(i, {}).get("id", i) for i in ids]
ids += [L["id"] for p in nb["packs"] for L in p["levels"]]
scores = {i: out[i] for i in ids if i in out}
missing = [i for i in ids if i not in out]
json.dump(scores, open(os.path.join(ROOT, "ios/ChipmunkChallenge/Native/board-scores.json"), "w"),
          separators=(",", ":"))
print(f"{len(scores)} of {len(ids)} boards have scores; missing: {missing[:20]}{' …' if len(missing) > 20 else ''}")
