"""Make the game's Level Play boards the new board maker's boards (2026-11-12): the pilot boards Brian rated 3+ stars.

Writes Engine/Sources/ChipmunkEngine/Resources/boards.json with "retire": true, so the original 170 boards and the
clipart packs leave Level Play (Coin Mining keeps its pictures). Each subject's best board comes first, best stars
first. Only each subject's best board plays (no duplicates), in one flat list (no packs).
"""
import csv, json, pathlib, sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))
from palette20 import limit  # noqa: E402
pilot = {b["id"]: b for b in json.load(open(ROOT / "ios/ChipmunkChallenge/Native/pilot-boards.json"))}
rated = [r for r in csv.DictReader(open(ROOT / "tools/packs/ratings-pilot-2026-11-12.csv")) if r["level"] == "new"]
keep = sorted((r for r in rated if int(r["stars"]) >= 3), key=lambda r: (-int(r["stars"]), -int(r["claude_score"]), r["id"]))
first, second, seen = [], [], set()
for r in keep:
    (second if r["name"] in seen else first).append(r)
    seen.add(r["name"])
order = first  # one board per subject (2026-11-13: the second versions played as duplicates)
boards = [{"id": r["id"], "name": pilot[r["id"]]["name"], "rows": limit(pilot[r["id"]]["rows"])} for r in order]
out = ROOT / "Engine/Sources/ChipmunkEngine/Resources/boards.json"
old = json.load(open(out)) if out.exists() else {}
json.dump({"retire": True, "levels": boards, "mining": old.get("mining", [])}, open(out, "w"), separators=(",", ":"))
print(f"{len(boards)} boards -> {out}")
